import renom as rm
from renom.graph.core import UserLossGraph, operation, GraphMultiStorage, GraphFactory
import numpy as np


class smooth_l1_forward(operation):

    name = 'Smooth L1 (F)'
    roles = ['loss']

    def __init__(self, delta=1.0, reduction='mean'):
        self.delta = delta
        self.reduction = reduction

    def setup(self, inputs):
        predictions = inputs[0]['y']
        real_values = inputs[1]['y']
        self.gpus = predictions.gpus
        self._graph_input = predictions
        self._label_input = real_values

        out_shape = predictions.shape if self.reduction is None else (1, )
        assert predictions.shape == real_values.shape
        output = GraphMultiStorage(shape=out_shape, gpus=predictions.gpus)

        self._vars = {'y': output}
        self._outputs = output
        self._N = predictions.shape[0]

    def perform(self):
        self._d = GraphMultiStorage(shape=self._graph_input.shape, gpus=self.gpus)
        for gpu, handle in rm.cuda.RenomHandlers(self.gpus):
            x = self._graph_input[gpu].new_array()
            y = self._label_input[gpu].new_array()
            N = len(x)
            d = x - y
            delta = self.delta
            abs_d = abs(d)
            flag = abs_d < delta
            ret = (flag * 0.5 * (d * d) + (1 - flag) * (abs_d - 0.5 * delta) * delta)
            if self.reduction is None:
                pass
            else:
                ret = np.sum(ret).reshape(1,)
                if self.reduction == 'mean':
                    ret /= N
                elif self.reduction == 'sum':
                    pass
            self._d[gpu] = d
            self._outputs[gpu].to_gpu(ret)


class smooth_l1_forward_cpu(smooth_l1_forward):

    def perform(self):
        x = self._graph_input['cpu']
        y = self._label_input['cpu']
        N = len(x)
        d = x - y
        delta = self.delta
        abs_d = abs(d)
        flag = abs_d < delta
        ret = flag * 0.5 * (d * d) + (1 - flag) * (abs_d - 0.5 * delta) * delta

        if self.reduction is None:
            pass
        else:
            ret = np.sum(ret).reshape(1,)
            if self.reduction == 'mean':
                ret /= N
            elif self.reduction == 'sum':
                pass
        self._d = d
        self._outputs['cpu'] = ret


class smooth_l1_backward(operation):

    name = 'Smooth L1 (B)'

    def __init__(self, associated_forward):
        self._fwd_op = associated_forward
        self.delta = self._fwd_op.delta

    def setup(self, inputs):
        self.reduction = self._fwd_op.reduction

        if len(inputs) > 3:
            self._dy = inputs[3]['y']
        else:
            self._dy = None
        predictions = inputs[0]['y']
        real_values = inputs[1]['y']
        self._graph_input = predictions
        self._label_input = real_values
        gpus = predictions.gpus
        self.gpus = gpus
        output = GraphMultiStorage(shape=predictions.shape, gpus=gpus)
        self._outputs = output
        self._vars = {'y': output, 'dy': output, id(self._fwd_op._graph_input): output}
        self._N = predictions.shape[0]

    def perform(self):
        for gpu, handle in rm.cuda.RenomHandlers(self.gpus):
            if self._dy is not None:
                dy = self._dy[gpu]
            else:
                dy = 1
            d = self._fwd_op._d[gpu]
            N = len(d)
            delta = self.delta
            mask = abs(d) <= delta
            sign = (d > 0) * 2 - 1
            ret = mask * d + (1 - mask) * sign * delta
            if self.reduction is None:
                pass
            else:
                if self.reduction == 'mean':
                    ret = ret / N
                elif self.reduction == 'sum':
                    pass
                else:
                    pass
            self._outputs[gpu].to_gpu(ret)
            rm.cuda.cumul(self._outputs[gpu], dy, self._outputs[gpu], handle)


class smooth_l1_backward_cpu(smooth_l1_backward):

    def perform(self):
        if self._dy is not None:
            dy = self._dy['cpu']
        else:
            dy = 1
        d = self._fwd_op._d
        N = len(d)
        delta = self.delta
        mask = abs(d) <= delta
        sign = (d > 0) * 2 - 1
        ret = mask * d + (1 - mask) * sign * delta
        if self.reduction is None:
            pass
        else:
            if self.reduction == 'mean':
                ret /= N
            elif self.reduction == 'sum':
                pass
            else:
                pass
        self._outputs['cpu'] = ret * dy


class SmoothL1Element(UserLossGraph):

    def __init__(self, delta=1.0, reduction='mean', previous_elements=None):
        self.delta = delta
        fwd_op = smooth_l1_forward(delta, reduction) \
            if rm.is_cuda_active() else smooth_l1_forward_cpu(delta, reduction)
        bwd_ops = [smooth_l1_backward(fwd_op) if rm.is_cuda_active()
                   else smooth_l1_backward_cpu(fwd_op)]
        super().__init__(forward_operation=fwd_op, backward_operations=bwd_ops, previous_elements=previous_elements)


class SmoothL1(GraphFactory):
    """A factory class of smooth l1 loss function element.

    Args:
        delta (float):

    +-----------+-------------------------------------------------------+
    | reduction |  description                                          |
    +===========+=======================================================+
    |  'mean'   | Calculates mean along axis=0 then sum up all element. |
    +-----------+-------------------------------------------------------+
    |  'sum'    | Calculates sum of all element.                        |
    +-----------+-------------------------------------------------------+
    |   None    | Reduction is not performed.                           |
    +-----------+-------------------------------------------------------+

    """

    def prepare(self, delta=1.0, reduction='mean'):
        self.delta = delta
        self.reduction = reduction

    def connect(self, predictions, true_values):
        ret = SmoothL1Element(self.delta, self.reduction,
                              previous_elements=[predictions, true_values])
        return ret
