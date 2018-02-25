Changes 2.3.1 => 2.4.1
============================================

Modified
^^^^^^^^

**#1.** GPU accelerated __getitem__, __setitem__ is available.

    The performance become better.

    Result of executing getitem on matrix 'n' for 1000 times.
    The shape of 'n' is (1000, 1000).

    .. csv-table::
        :header: getitem, v2.3.1[sec], v2.4.1[sec]

        "n[0, 0]", 0.51686, 0.08107
        "n[0]", 0.52871, 0.08351
        "n[:, :]", 1.50995, 0.16364


**#2.** renom.concat() accepts variable length argument list.

    The following code became available.

        >>> import renom
        >>> import renom as rm
        >>> import numpy as np
        >>>
        >>> a = np.random.rand(2, 1)
        >>> b = np.random.rand(2, 2)
        >>> c = np.random.rand(2, 3)
        >>>
        >>> out = rm.concat(a, b, c) # Variable length argument can be passed.
        >>> out.shape
        (2, 6) 


**#3.** renom.sum() accepts 'axis' argument.

    The following code became available.

        >>> import renom as rm
        >>> import numpy as np
        >>>
        >>> a = np.random.rand(2, 1)
        >>> out = rm.sum(a)
        >>> out.shape
        ()
        >>> out = rm.sum(a, axis=0)
        >>> out.shape
        (1,)
        >>> out = rm.sum(a, axis=1)
        >>> out.shape
        (2,)


**#4.** Auto differentiation is enabled in functions 'T', 'transpose' and 'reshape' that are implemented in Node object.

    The following code became available.

        >>> import renom as rm
        >>> import numpy as np
        >>>
        >>> a = np.random.rand(2, 1)   
        >>> va = rm.Variable(a)
        >>>
        >>> print(rm.sum(va.T).grad().get(va)) # Auto differentiation of 'T'.
        [[ 1.]
         [ 1.]]
        >>> print(rm.sum(va.transpose(1, 0)).grad().get(va)) # AD of 'transpose'.
        [[ 1.]
         [ 1.]]
        >>> print(rm.sum(va.reshape(1, 1, 2)).grad().get(va) # AD of 'reshape'.
        [[ 1.]
         [ 1.]]


**#5.** In the Yolo class, redundant argument 'image_size' of the function '__init__' is removed.

    When you instantiate Yolo class, be careful not to give the argument 'image_size'.
    See API reference of :ref:`Yolo`.

**#6.** Users can save attributes when saving model's weight parameters.

    In the previous version, save and load function of Model object only dealt with weight parameters.
    In v2.4.1, you can save any attributes with save and load function.
    See the API reference of Model object.

**#7.** TDA modules are moved to ReNomTDA repository.

    You can install ReNomTDA from following URL.  
    ReNomTDA: https://github.com/ReNom-dev-team/ReNomTDA


New features
^^^^^^^^^^^^

**#1.** New auto differentiation available operation: renom.amax, renom.amin.

**#2.** New method for releasing gpu memory pool: renom.cuda.release_mem_pool.

Removed modules
^^^^^^^^^^^^^^

Nothing

Bug fix
^^^^^^^

**#1.** Broadcasting matrix arithmetic operations.

    In the previous version, broadcasted calculations, as exampled bellow, with gpu are
    not correctly calculated.

    Bug example:
        >>> import renom as rm
        >>> import numpy as np
        >>> from renom.cuda import set_cuda_active
        >>>
        >>> set_cuda_active(False)
        >>> a = rm.Variable(np.arange(2).reshape(1, 2))
        >>> print(a)
        [[ 0.,  1.]]
        >>>
        >>> b = rm.Variable(np.arange(2).reshape(2, 1))
        >>> print(b) 
        [[ 0.],
         [ 1.]]
        >>>
        >>> c = a + b # CPU is correct.
        >>> print(c)
        [[ 0.,  1.],
         [ 1.,  2.]]
        >>>
        >>> set_cuda_active(True)
        >>> c = a + b # GPU was not correct.
        >>> print(c)
        [[ 0.,  2.],
         [ 0.,  0.]]

    This bug have been happened when following conditions were satisfied.

    1. Calculation on your own define computational graph using Variable object's arithmetic operations.
    2. Calculation with GPU.
    3. Broadcasting(ex: multiplying different shaped matrix). 
    4. Either matrix's last dimension size is 1 and another matrix's last dimension size is not 1.

    If only sequential models have been used, this bug have not affected.


**#2.** Batch normalization inference calculation.

    In the previous version, inference calculation of batch normalization were stopped by
    CUDNN_STATUS_BAD_PARAM error.

    Bug example:
        >>> import renom as rm
        >>> import numpy as np
        >>> from renom.cuda import set_cuda_active
        >>>
        >>> layer = rm.BatchNormalize()
        >>> layer.set_models(inference=True) # Setting the layer as inference mode.
        >>> a = rm.Variable(np.arange(2).reshape(2, 1))
        >>> c = layer(a).as_ndarray()
        Exception: b'CUDNN_STATUS_BAD_PARAM'

    This bug have been happened when following conditions were satisfied.

    1. Calculation with GPU.
    2. Executes the inference mode without executing the training mode even once.

