#!/usr/bin/env python
# -*- coding: utf-8 -*-
from __future__ import division
import warnings
import numpy as np
from renom.core import get_gpu, Node
from renom.cuda import is_cuda_active
from renom.cuda.cuda_base import pinNumpy, initPinnedMemory


class Distributor(object):
    '''Distributor class
    This is the base class of a data distributor.

    Args:
        x (ndarray): Input data.
        y (ndarray): Target data.
        path (string): Path to data.

    >>> import numpy as np
    >>> from renom.utility.distributor.distributor import NdarrayDistributor
    >>> x = np.random.randn(100, 100)
    >>> y = np.random.randn(100, 1)
    >>> distributor = NdarrayDistributor(x, y)
    >>> batch_x, batch_y = distributor.batch(10).next()
    >>> batch_x.shape
    (10, 100)
    >>> batch_y.shape
    (10, 1)

    '''

    def __init__(self, x=None, y=None, path=None, data_table=None):
        self._folder_path = path
        self._data_x = x
        self._data_y = y
        self._data_table = data_table
        self._data_size = None

    def __getitem__(self, index):
        if isinstance(index, slice):
            start, stop, step = index.start, index.stop, index.step
            return self.__class__(x=self._data_x[start:stop:step],
                                  y=self._data_y[start:stop:step],
                                  data_table=self._data_table)
        else:
            return self._data_x[index], self._data_y[index]

    def __len__(self):
        return self._data_size

    def batch(self, batch_size, shuffle=True):
        '''
        This function returns `minibatch`.

        Args:
            batch_size (int): Size of batch.
            shuffle (bool): If True is passed, data will be selected randomly.
        '''
        if shuffle:
            perm = np.random.permutation(self._data_size)
            for i in range(int(np.ceil(self._data_size / batch_size))):
                p = perm[i * batch_size:(i + 1) * batch_size]
                yield self._data_x[p], self._data_y[p]
        else:
            for i in range(int(np.ceil(self._data_size / batch_size))):
                yield self._data_x[i * batch_size:(i + 1) * batch_size], \
                    self._data_y[i * batch_size:(i + 1) * batch_size]

    def kfold(self, num, overlap=False, shuffle=False):
        for i in range(num):
            yield self._data_x

    def split(self, ratio=0.8, shuffle=True):
        '''
        This method splits its own data and generates 2 distributors using the split data.

        Args:
            ratio (float): Ratio for dividing data.
            shuffle (bool): If True, the data is shuffled before dividing.
        '''
        div = int(self._data_size * ratio)
        if shuffle:
            perm = np.random.permutation(self._data_size)
        else:
            perm = np.arange(self._data_size)

        for i in range(2):
            p = perm[div * i:div * (i + 1)]
            yield self.__class__(x=self._data_x[p],
                                 y=self._data_y[p],
                                 data_table=self._data_table)

    def data(self):
        return self._data_x, self._data_y

    @property
    def y(self):
        return self._data_y

    @property
    def x(self):
        return self._data_x


class NdarrayDistributor(Distributor):

    '''
    Derived class of Distributor which manages ndarray data.

    Args:
        x (ndarray): Input data.
        y (ndarray): Target data.
    '''

    def __init__(self, x, y, **kwargs):
        super(NdarrayDistributor, self).__init__(x=x, y=y,
                                                 data_table=kwargs.get("data_table"))
        assert len(x) == len(y), "{} {}".format(len(x), len(y))
        self._data_size = len(x)

    def kfold(self, num=4, overlap=False, shuffle=True):
        if num < 2:
            warnings.warn(
                "If the argument 'num' is less than 2, it returns a pair of 'self' and 'None'.")
            yield self, None
            return
        div = int(np.ceil(self._data_size / num))
        flag = np.zeros((self._data_size))
        for i in range(num):
            flag[i * div:].fill(i)

        if shuffle:
            perm = np.random.permutation(self._data_size)
        else:
            perm = np.arange(self._data_size)

        for i in range(num):
            ty_flag = np.where(flag == i, False, True)
            ts_flag = np.where(flag == i, True, False)
            yield self.__class__(x=self._data_x[perm[ty_flag]],
                                 y=self._data_y[perm[ty_flag]],
                                 data_table=self._data_table),\
                self.__class__(x=self._data_x[perm[ts_flag]],
                               y=self._data_y[perm[ts_flag]],
                               data_table=self._data_table)



class GPUDistributor(Distributor):

    '''
    Derived class of Distributor which manages GPUValue data.

    Args:
        x (ndarray): Input data.
        y (ndarray): Target data.
    '''

    def __init__(self, x, y):
        assert is_cuda_active(), "Cuda must be activated to use GPU distributor"
        super(GPUDistributor, self).__init__(x=x, y=y)
        assert len(x) == len(y), "Input batches must have same number as output batches"
        self._data_size = len(x)

    def __getitem__(self, index):
        return super(GPUDistributor, self).__getitem__(self, index)

    def kfold(self, num=4, overlap=False, shuffle=True):
        return super(GPUDistributor, self).kfold(self, num, overlap, shuffle)

    @staticmethod
    def preload_single(batch):
        pinNumpy(batch)
        return get_gpu(batch)

    @staticmethod
    def preload_pair(batch1, batch2):
        return GPUDistributor.preload_single(batch1), GPUDistributor.preload_single(batch2)

    @staticmethod
    def create_return(batch1, batch2):
        return batch1, batch2

    def batch(self, batch_size, shuffle=True):
        generator = super(GPUDistributor, self).batch(batch_size, shuffle)
        notEmpty = True
        first = True
        while(notEmpty):
            try:
                # On entering, we preload the first two batches
                if first:
                    b = next(generator)
                    initPinnedMemory(b[0])
                    x1, y1 = GPUDistributor.preload_pair(b[0], b[1])
                    first = False

                # We continue to preload an extra batch until we are finished
                # Values yet to be returned are stored in *2
                b = next(generator)
                x2, y2 = GPUDistributor.preload_pair(b[0], b[1])

                yield GPUDistributor.create_return(x1, y1)
                # Release currently released values and store the next as
                # next to be yielded in *1
                x1, y1 = x2, y2

            # When kicked out of the loop, return the last pre-loaded values
            except StopIteration:
                notEmpty = False
            # Check if there was only a single batch
            if not first:
                yield GPUDistributor.create_return(x2, y2)
            else:
                yield GPUDistributor.create_return(x1, y1)



class TimeSeriesDistributor(NdarrayDistributor):

    def __init__(self, x, y, **kwargs):
        super(TimeSeriesDistributor, self).__init__(x=x, y=y,
                                                    data_table=kwargs.get("data_table"))
        assert x.ndim == 3
        assert len(x) == len(y)
        self._data_size = len(x)
