import numpy as np
import renom as rm
rm.set_cuda_active()
#np.set_printoptions(precision = 2, suppress = True)

def compare(nd_value, ad_value):
  print('nd=')
  print(nd_value)
  print('ad=')
  print(ad_value)
  assert np.allclose(nd_value, ad_value)

def getNumericalDiff( lossMethod, testValue ):
  assert isinstance(testValue, rm.graph.core.multi_gpu_variable)
  coefficients1 = [ 1, -8, 8, -1 ]
  coefficients2 = [ -2, -1, 1, 2 ]
  c = 12
  eps = np.sqrt(np.finfo(rm.precision).eps)

  def store_value(index, storage, value):
    v = storage[0]
    tmp = np.empty(v.shape, dtype = rm.precision)
    v.to_cpu(tmp)
    tmp[index] += value
    v.to_gpu(tmp)

  def retrieve_value(index, storage):
    v = storage[0]
    tmp = np.empty(v.shape, dtype = rm.precision)
    v.to_cpu(tmp)
    return tmp[index]


  diff = np.zeros(testValue.shape)
  for nindex in np.ndindex(diff.shape):
    loss = 0
    for i in range(len(coefficients1)):
      k = retrieve_value(nindex, testValue)
      dx = eps * k if k != 0 else eps
      store_value(nindex, testValue, coefficients2[i] * dx)
      ret = lossMethod() * coefficients1[i]
      store_value(nindex, testValue, -coefficients2[i] * dx)
      loss += ret

    v = loss / (dx * c)
    diff[nindex] = v
  return diff

def test_dense():

  v = np.random.rand(1,2)
  val = rm.graph.StaticVariable(v)
  model = rm.graph.DenseGraphElement(output_size = 2)
  l = rm.graph.ConstantLossElement()
  m = model(val)
  loss = l(m)

  ad = loss.backward().get_gradient(val.value).as_ndarray()
  def func():
    m.forward()
    loss.forward()
    ret = loss.as_ndarray()
    return ret
  
  compare( getNumericalDiff( func , val.value ) , ad )
  compare( getNumericalDiff( func , model.weights) , loss.backward().get_gradient(model.weights).as_ndarray())
  


if __name__ == '__main__':
  test_dense()
