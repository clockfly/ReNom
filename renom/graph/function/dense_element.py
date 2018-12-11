from renom.graph.core import learnable_graph_element, operational_element, operation, multi_gpu_variable, GraphFactory, graph_variable
import renom.utility.initializer as init
import renom as rm
import numpy as np

class dense_forward(operation):

  name = 'Dense (F)'
  consumes = ['w']

  def __init__(self, output_size):
    
    self._output_size = output_size

  def setup(self, inputs, storage):
    weights = inputs[1]['y']
    inputs = inputs[0]['y']
    assert isinstance(inputs, multi_gpu_variable), 'Received {}'.format(type(inputs))
    self.gpus = inputs.gpus
    self._init = init.GlorotNormal()
    self._inputs = inputs
    weight_shape = ( inputs.shape[1] , self._output_size )
    weights.__init__( shape = weight_shape , gpus = self.gpus, initializer = self._init)
    output_shape = ( inputs.shape[0] , self._output_size )
    outputs = multi_gpu_variable( shape = output_shape, gpus = self.gpus)
    self._vars = {'x' : inputs, 'w' : weights, 'y' : outputs}
    self._weights = weights
    self._outputs = outputs

  def perform(self):
    for gpu, handle in rm.cuda.RenomHandlers(self.gpus):
      rm.cuda.cublas_gemm(self._inputs[gpu], 0, self._weights[gpu], 0, self._outputs[gpu], handle)


class dense_forward_cpu(dense_forward):

  def perform(self):
    ret = np.dot(self._inputs['cpu'], self._weights['cpu'])
    self._outputs['cpu'] = ret

class dense_backward(operation):

  name = 'Dense (B)'

  def __init__(self, associated_forward):
    self._fwd_op = associated_forward

  def setup(self, inputs, storage):

    inputs = inputs[0]['dy']
    gpus = inputs.gpus
    self.gpus = gpus
    weights = self._fwd_op.get_key('w')
    self._inputs = inputs
    self._weights = weights

    fwd_ins = self._fwd_op.get_key('x')
    output_shape = fwd_ins.shape

    outputs = multi_gpu_variable(shape = output_shape, gpus = gpus, initializer = None)

    self._vars = { 'y' : outputs, 'dy' : outputs , id(fwd_ins) : outputs}
    self._outputs = outputs

  def perform(self):
    for gpu, handle in rm.cuda.RenomHandlers(self.gpus):
      rm.cuda.cublas_gemm(self._inputs[gpu], 0, self._weights[gpu], 1, self._outputs[gpu], handle)

class dense_backward_cpu(dense_backward):

  def perform(self):
    ret = np.dot(self._inputs['cpu'], self._weights['cpu'].T)
    self._outputs['cpu'] = ret


class dense_weight_backward(operation):

  name = 'Dense Weight (B)'
  produces = ['w']

  def __init__(self, associated_forward):
    self._fwd_op = associated_forward


  def setup(self, inputs, storage):
    inputs = inputs[0]['dy']
    self._inputs = inputs

    gpus = inputs.gpus
    self.gpus = gpus
    fwd_ins = self._fwd_op.get_key('x')
    fwd_weights = self._fwd_op.get_key('w')
    output_shape = fwd_weights.shape

    outputs = multi_gpu_variable(shape = output_shape, gpus = gpus, initializer = None)

    self._vars = { 'y' : outputs, 'w' : outputs , id(fwd_weights) : outputs }

    self._fwd_ins = fwd_ins
    self._outputs = outputs
    
  def perform(self):
    for gpu, handle in rm.cuda.RenomHandlers(self.gpus):
      rm.cuda.cublas_gemm(self._fwd_ins[gpu], 1, self._inputs[gpu], 0, self._outputs[gpu], handle)

class dense_weight_backward_cpu(dense_weight_backward):

  def perform(self):
    ret = np.dot(self._fwd_ins['cpu'].T, self._inputs['cpu'])
    self._outputs['cpu'] = ret

class DenseGraph(learnable_graph_element):

  has_back = True

  def __init__(self, output_size, previous_element = None):
    
    fwd_op = dense_forward(output_size) if rm.is_cuda_active() else dense_forward_cpu(output_size)
    bwd_ops = [ dense_backward(associated_forward = fwd_op) if rm.is_cuda_active() else dense_backward_cpu(fwd_op),
                dense_weight_backward(associated_forward = fwd_op) if rm.is_cuda_active() else dense_weight_backward_cpu(fwd_op),
              ]
    self.output_size = output_size

    super().__init__(forward_operation = fwd_op, backward_operations = bwd_ops, previous_elements = previous_element)

class DenseGraphElement(GraphFactory):

  def __init__(self, output_size):    
    super().__init__()
    self.output_size = output_size
    self.params['w'] = graph_variable()
    self._bias = rm.graph.BiasGraphElement()
    self.params['b'] = self._bias.params['b']

  def connect(self, other):
    ret = DenseGraph(output_size = self.output_size, previous_element = [ other, self.params['w']])
    ret = self._bias(ret)
    return ret
