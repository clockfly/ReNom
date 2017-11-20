#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
関数命名規則
関数名: cu〜    (python側から呼ばれる関数)
        
引数名: gpu_value
"""
import numpy as np
from libc.stdint cimport uintptr_t
from libcpp cimport bool
import cuda_base
import operator
import functools
import renom.core
import renom.cuda


def cunegate(input, result):
    cuda_base.check_heap_device(input, result)

    cdef VALUE_TYPE * first = <VALUE_TYPE * > < uintptr_t > input._ptr
    cdef VALUE_TYPE * last = first + <size_t > input.size
    cdef VALUE_TYPE * output = <VALUE_TYPE * > < uintptr_t > result._ptr
    thrust_negate(first, last, output)


def curelu_foward(gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_relu_forward(ptr1, ptr2, size)


def curelu_backard(gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_relu_backward(ptr1, ptr2, size)


def culeaky_leru_forward(s, gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_leaky_relu_forward(< VALUE_TYPE > s, ptr1, ptr2, size);


def culeaky_leru_backward(s, gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_leaky_relu_backward(< VALUE_TYPE > s, ptr1, ptr2, size);


def cueru_forward(s, gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_elu_forward(< VALUE_TYPE > s, ptr1, ptr2, size);


def cueru_backward(s, gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_elu_backward(< VALUE_TYPE > s, ptr1, ptr2, size);


def cusigmoid(gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_sigmoid(ptr1, ptr2, size)


def cutanh(gpu_value1, gpu_value2):
    cuda_base.check_heap_device(gpu_value1, gpu_value2)

    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_tanh(ptr1, ptr2, size)


cdef basic_operation(Operation op, gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)

    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2
    cdef VALUE_TYPE * ptr3 = <VALUE_TYPE * > < uintptr_t > gpu_value3._ptr
    cdef int elem_size_a = gpu_value1.size
    cdef int elem_size_b
    if hasattr(gpu_value2, "_ptr"):
        ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
        value = 0
        elem_size_b = gpu_value2.size
    else:
        ptr2 = <VALUE_TYPE * >0
        value = gpu_value2
        elem_size_b = 1
    thrust_operation(op, < VALUE_TYPE > value, elem_size_a, ptr1, elem_size_b, ptr2, ptr3)


def cumul(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.MUL, gpu_value1, gpu_value2, gpu_value3)


def cuadd(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.ADD, gpu_value1, gpu_value2, gpu_value3)


def cusub(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.SUB, gpu_value1, gpu_value2, gpu_value3)


def cudiv(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.DIV, gpu_value1, gpu_value2, gpu_value3)


def curdiv(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.RDIV, gpu_value1, gpu_value2, gpu_value3)


def cupow(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.POW, gpu_value1, gpu_value2, gpu_value3)


def curpow(gpu_value1, gpu_value2, gpu_value3):
    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    basic_operation(Operation.RPOW, gpu_value1, gpu_value2, gpu_value3)


def cufill(value, gpu_value):
    cdef int size = <int > gpu_value.size
    cdef VALUE_TYPE v = <VALUE_TYPE > value
    cdef VALUE_TYPE * ptr = <VALUE_TYPE * > < uintptr_t > gpu_value._ptr

    cuda_base.check_heap_device(gpu_value)
    thrust_fill(v, ptr, size)


def culoge(gpu_value1, gpu_value2):
    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_loge(ptr1, ptr2, size)


def cuexp(gpu_value1, gpu_value2):
    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    thrust_exp(ptr1, ptr2, size)


def cusqrt(gpu_value1, gpu_value2):
    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_sqrt(ptr1, ptr2, size)

def cusign(gpu_value1, gpu_value2):
    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > gpu_value2._ptr
    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_sign(ptr1, ptr2, size)

def cucross_entropy(gpu_value1, gpu_value2, gpu_value3):
    cdef int size = <int > gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE * ptr3 = <VALUE_TYPE * > < uintptr_t > gpu_value3._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)
    thrust_cross_entropy(ptr1, ptr2, ptr3, size)


def cubroadcast(gpu_value1, gpu_value2):
    cdef int size_1 = <int > gpu_value1.size
    cdef int size_2 = <int > gpu_value2.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_broad_cast(size_1, ptr1, size_2, ptr2)


def cuabs_forward(gpu_value1, gpu_value2):
    cdef int size = gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_abs_forward(ptr1, ptr2, size)


def cuabs_backward(gpu_value1, gpu_value2):
    cdef int size = gpu_value1.size
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_abs_backward(ptr1, ptr2, size)


def cumin(value, gpu_value1, gpu_value2=None):
    cdef int size = gpu_value1.size
    cdef VALUE_TYPE * ptr1 = < VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = < VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE v = <VALUE_TYPE > value

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_min(v, ptr1, ptr2, size)


def cumax(value, gpu_value1, gpu_value2=None):
    cdef int size = gpu_value1.size
    cdef VALUE_TYPE * ptr1 = < VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = < VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE v = <VALUE_TYPE > value

    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_max(v, ptr1, ptr2, size)


def curoi_pool2d_forward(rois, x, spatial_scale, channels, height,
                        width, outh, outw, z, augmax_data):
    cdef int N = rois.shape[0]

    cdef VALUE_TYPE * ptr_x = <VALUE_TYPE * > < uintptr_t> x._ptr
    cdef VALUE_TYPE * ptr_rois = <VALUE_TYPE  *> < uintptr_t> rois._ptr
    cdef VALUE_TYPE * ptr_z = <VALUE_TYPE * > < uintptr_t> z._ptr
    cdef VALUE_TYPE * ptr_augmax_data = <VALUE_TYPE * > < uintptr_t> augmax_data._ptr
    thrust_forward_roi_pool2d(N, ptr_x, spatial_scale, channels, height, width, outh, outw, ptr_rois, ptr_z, ptr_augmax_data)

def curoi_pool2d_backward(du, argmax, rois, spatial_scale, ch, h, w, outh, outw, dx):
    cdef int N = rois.shape[0]

    cdef VALUE_TYPE * ptr_du = <VALUE_TYPE *> < uintptr_t> du._ptr
    cdef VALUE_TYPE * ptr_argmax = <VALUE_TYPE * > < uintptr_t> argmax._ptr
    cdef VALUE_TYPE * ptr_rois = <VALUE_TYPE  *> < uintptr_t> rois._ptr
    cdef VALUE_TYPE * ptr_dx = <VALUE_TYPE * > < uintptr_t> dx._ptr
    thrust_backward_roi_pool2d(N, ptr_du, ptr_argmax, ptr_rois, spatial_scale, ch, h, w, outh, outw, ptr_dx)

def culstm_forward_activate(u):
    cdef int N = u.shape[0]
    cdef int M = u.shape[1]

    cdef VALUE_TYPE * ptr_u = < VALUE_TYPE * > < uintptr_t > u._ptr
    thrust_forward_lstm_activate(N, M, ptr_u)


def culstm_forward(u, s, ps, z):
    cdef int N = u.shape[0]
    cdef int M = u.shape[1]

    cdef VALUE_TYPE * ptr_u = < VALUE_TYPE * > < uintptr_t > u._ptr
    cdef VALUE_TYPE * ptr_s = < VALUE_TYPE * > < uintptr_t > s._ptr
    cdef VALUE_TYPE * ptr_ps = < VALUE_TYPE * > < uintptr_t > ps._ptr
    cdef VALUE_TYPE * ptr_z = < VALUE_TYPE * > < uintptr_t > z._ptr
    thrust_forward_lstm(N, M, ptr_u, ptr_s, ptr_ps, ptr_z)


def culstm_backward(u, du, s, ps, e, pgf, dou, dou_n, temporal):
    cdef int N = u.shape[0]
    cdef int M = u.shape[1]
    cdef VALUE_TYPE * ptr_u = < VALUE_TYPE * > < uintptr_t > u._ptr
    cdef VALUE_TYPE * ptr_du = < VALUE_TYPE * > < uintptr_t > du._ptr
    cdef VALUE_TYPE * ptr_s = < VALUE_TYPE * > < uintptr_t > s._ptr
    cdef VALUE_TYPE * ptr_ps = < VALUE_TYPE * > < uintptr_t > ps._ptr
    cdef VALUE_TYPE * ptr_e = < VALUE_TYPE * > < uintptr_t > e._ptr
    cdef VALUE_TYPE * ptr_pgf = < VALUE_TYPE * > < uintptr_t > pgf._ptr
    cdef VALUE_TYPE * ptr_dou = < VALUE_TYPE * > < uintptr_t > dou._ptr
    cdef VALUE_TYPE * ptr_dou_n = < VALUE_TYPE * > < uintptr_t > dou_n._ptr
    cdef bool temp = temporal
    thrust_backward_lstm(N, M, ptr_u, ptr_du, ptr_s, ptr_ps,
                         ptr_e, ptr_pgf, ptr_dou, ptr_dou_n, temp)


def cupeepholelstm_forward(u, wc, prestate, state, z):
    cuda_base.check_heap_device(u, prestate, state, wc, z)

    cdef int N = u.shape[0]
    cdef int M = u.shape[1]
    cdef VALUE_TYPE * ptr_u = < VALUE_TYPE * > < uintptr_t > u._ptr
    cdef VALUE_TYPE * ptr_z = < VALUE_TYPE * > < uintptr_t > z._ptr
    cdef VALUE_TYPE * ptr_ps = < VALUE_TYPE * > < uintptr_t > prestate._ptr
    cdef VALUE_TYPE * ptr_s = < VALUE_TYPE * > < uintptr_t > state._ptr
    cdef VALUE_TYPE * ptr_wc = < VALUE_TYPE * > < uintptr_t > wc._ptr
    thrust_forward_peephole_lstm(N, M, ptr_u, ptr_wc, ptr_ps, ptr_s, ptr_z)


def cupeepholelstm_backward(u, prestate, state, prefg, wc, dy, drt, dot, dr, dou, dwc, temporal):
    cuda_base.check_heap_device(u, prestate, state, prestate, wc,
                                dy, drt, dot, dou, dr, dwc, temporal)
    cdef int N = u.shape[0]
    cdef int M = u.shape[1]

    cdef VALUE_TYPE * ptr_u = < VALUE_TYPE * > < uintptr_t > u._ptr
    cdef VALUE_TYPE * ptr_ps = < VALUE_TYPE * > < uintptr_t > prestate._ptr
    cdef VALUE_TYPE * ptr_s = < VALUE_TYPE * > < uintptr_t > state._ptr
    cdef VALUE_TYPE * ptr_pfg = < VALUE_TYPE * > < uintptr_t > prefg._ptr
    cdef VALUE_TYPE * ptr_wc = < VALUE_TYPE * > < uintptr_t > wc._ptr
    cdef VALUE_TYPE * ptr_dy = < VALUE_TYPE * > < uintptr_t > dy._ptr
    cdef VALUE_TYPE * ptr_drt = < VALUE_TYPE * > < uintptr_t > drt._ptr
    cdef VALUE_TYPE * ptr_dot = < VALUE_TYPE * > < uintptr_t > dot._ptr
    cdef VALUE_TYPE * ptr_dr = < VALUE_TYPE * > < uintptr_t > dr._ptr
    cdef VALUE_TYPE * ptr_dou = < VALUE_TYPE * > < uintptr_t > dou._ptr
    cdef VALUE_TYPE * ptr_dwc = < VALUE_TYPE * > < uintptr_t > dwc._ptr
    cdef bool temp = temporal
    thrust_backward_peephole_lstm(N, M, ptr_u, ptr_ps, ptr_s, ptr_pfg, ptr_wc,
                                  ptr_dy, ptr_drt, ptr_dot, ptr_dr, ptr_dou, ptr_dwc, temp)


def cubinarize(gpu_value1, th, gpu_value2):
    cdef int N = gpu_value1.size
    cdef VALUE_TYPE * gpu_ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * gpu_ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE threathold = th
    cuda_base.check_heap_device(gpu_value1, gpu_value2)
    thrust_binarize(gpu_ptr1, threathold, N, gpu_ptr2)


def cuembedding_forward(gpu_value1, weight, gpu_value2):
    cdef int N = gpu_value1.shape[0]
    cdef int K = weight.shape[0]
    cdef int M = weight.shape[1]
    cdef VALUE_TYPE * gpu_ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * gpu_ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE * weight_ptr = <VALUE_TYPE * > < uintptr_t > weight._ptr
    cuda_base.check_heap_device(gpu_value1, gpu_value2, weight)
    thrust_embedding_forward(N, K, M, gpu_ptr1, weight_ptr, gpu_ptr2)


def cuembedding_backward(gpu_index, gpu_dy, gpu_dx):
    cdef int N = gpu_index.shape[0]
    cdef int K = gpu_dx.shape[0]
    cdef int M = gpu_dx.shape[1]
    cdef VALUE_TYPE * index_ptr = <VALUE_TYPE * > < uintptr_t > gpu_index._ptr
    cdef VALUE_TYPE * dy_ptr = <VALUE_TYPE * > < uintptr_t > gpu_dy._ptr
    cdef VALUE_TYPE * dx_ptr = <VALUE_TYPE * > < uintptr_t > gpu_dx._ptr
    cuda_base.check_heap_device(gpu_dy, gpu_index, gpu_dx)
    thrust_embedding_backward(N, K, M, index_ptr, dy_ptr, dx_ptr)


def cuconcat(gpu_value1, gpu_value2, gpu_value3, axis):

    cuda_base.check_heap_device(gpu_value1, gpu_value2, gpu_value3)

    cdef size_t size = gpu_value1.nbytes + gpu_value2.nbytes
    if gpu_value3.nbytes < size:
        raise ValueError("Insufficient destination buffer size")

    if (not gpu_value1.shape) or (not gpu_value2.shape):
        raise ValueError("zero-dimensional arrays cannot be concatenated")

    s1 = gpu_value1.shape[:axis] + gpu_value1.shape[axis + 1:]
    s2 = gpu_value1.shape[:axis] + gpu_value1.shape[axis + 1:]

    if s1 != s2:
        raise ValueError("all the input array dimensions except"
                         " for the concatenation axis must match exactly")

    cdef size_t size1 = functools.reduce(operator.__mul__, gpu_value1.shape[axis:], 1)
    cdef size_t size2 = functools.reduce(operator.__mul__, gpu_value2.shape[axis:], 1)
    cdef size_t rec_size = size1 + size2

    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value2._ptr
    cdef VALUE_TYPE * ptr3 = <VALUE_TYPE * > < uintptr_t > gpu_value3._ptr

    thrust_copy_memory_stride(ptr3, ptr1, gpu_value1.size, rec_size, size1)
    thrust_copy_memory_stride(ptr3 + size1, ptr2, gpu_value2.size, rec_size, size2)


ctypedef void(*REDUCE_FUNC)(VALUE_TYPE * a, const size_t nsize,
                            const size_t axis_size, const size_t elem_size,
                            const size_t child_size, VALUE_TYPE * b,
                            const size_t result_size)

cdef _reduce_array(gpu_value1, axis, REDUCE_FUNC f):
    cdef VALUE_TYPE xxx
    import renom.cuda
    nsize = functools.reduce(operator.__mul__, gpu_value1.shape, 1)

    if axis is None:
        axis_size = nsize
        elem_size = nsize
        child_size = 1
        result_shape = ()
        result_size = 1
    else:
        axis_size = gpu_value1.shape[axis]
        elem_size = functools.reduce(operator.__mul__, gpu_value1.shape[axis:], 1)
        child_size = functools.reduce(operator.__mul__, gpu_value1.shape[axis + 1:], 1)
        result_shape = gpu_value1.shape[:axis] + gpu_value1.shape[axis + 1:]
        result_size = np.product(result_shape, dtype=int)

    result = renom.core.GPUValue(shape=result_shape)

    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > gpu_value1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > result._ptr

    f(ptr1, nsize, axis_size, elem_size, child_size, ptr2, result_size)
    return result


def cusum(gpu_value1, axis=None):
    return _reduce_array(gpu_value1, axis, thrust_reduce_sum)


def cu_reduce_min(gpu_value1, axis=None):
    return _reduce_array(gpu_value1, axis, thrust_reduce_min)


def cu_reduce_max(gpu_value1, axis=None):
    return _reduce_array(gpu_value1, axis, thrust_reduce_min)


def cu_add_bias(bias, gpu_value):
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > < uintptr_t > bias._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > < uintptr_t > gpu_value._ptr
    cdef int size = <int > gpu_value.size
    cdef int wh = <int > (gpu_value.shape[2] * gpu_value.shape[3])
    cdef int n = <int > gpu_value.shape[0]
    thrust_add_bias(size, n, wh, ptr1, ptr2)

def cu_get_fg_ary_forward(ary, fg_ary):
    N = ary.shape[0] * ary.shape[1] * ary.shape[2] * ary.shape[3] * ary.shape[4]
    M = ary.shape[3] * ary.shape[4]
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > ary._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > fg_ary._ptr
    thrust_get_fg_ary_forward(N, M, ptr1, ptr2)

def cu_get_fg_ary_backward(du, zero):
    N = zero.shape[0] * zero.shape[1] * zero.shape[2] * zero.shape[3] * zero.shape[4]
    M = du.shape[3] * du.shape[4]
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > du._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > zero._ptr
    thrust_get_fg_ary_forward(N, M, ptr1, ptr2)

def cu_get_ith_ary_forward(ary, ith_ary, i):
    N = ary.size
    M = ary.size / ary.shape[0]
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > ary._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > ith_ary._ptr
    thrust_get_ith_ary_forward(N, M, i, ptr1, ptr2)

def cu_get_ith_ary_backward(du, zero, i):
    N = zero.size
    M = zero.size / zero.shape[0]
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > du._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > zero._ptr
    thrust_get_ith_ary_forward(N, M, i, ptr1, ptr2)

def cu_get_every_nth_ary(ary1, ary2, i, j):
    N = ary1.shape[0]
    M = ary1.shape[1]
    cdef VALUE_TYPE * ptr1 = <VALUE_TYPE * > <uintptr_t > ary1._ptr
    cdef VALUE_TYPE * ptr2 = <VALUE_TYPE * > <uintptr_t > ary2._ptr
    thrust_get_nth_ary(N, M, i, j, ptr1, ptr2)

def cu_assign_pred_box(x, y, w, h, ary):
    N, M = ary.shape
    cdef VALUE_TYPE * ary_ptr = <VALUE_TYPE *> <uintptr_t> ary._ptr
    cdef VALUE_TYPE * x_ptr = <VALUE_TYPE *> <uintptr_t> x._ptr
    cdef VALUE_TYPE * y_ptr = <VALUE_TYPE *> <uintptr_t> y._ptr
    cdef VALUE_TYPE * h_ptr = <VALUE_TYPE *> <uintptr_t> h._ptr
    cdef VALUE_TYPE * w_ptr = <VALUE_TYPE *> <uintptr_t> w._ptr
    thrust_assign_pred_box(N, M, x_ptr, y_ptr, h_ptr, w_ptr, ary_ptr)

def cu_pred_ctr(arg, length, ctr, ary):
    N, M = ary.shape
    cdef VALUE_TYPE *arg_ptr = <VALUE_TYPE *><uintptr_t> arg._ptr
    cdef VALUE_TYPE *length_ptr = <VALUE_TYPE *><uintptr_t> length._ptr
    cdef VALUE_TYPE *ctr_ptr = <VALUE_TYPE *><uintptr_t> ctr._ptr
    cdef VALUE_TYPE *ary_ptr = <VALUE_TYPE *><uintptr_t> ary._ptr
    thrust_pred_ctr(N, M, arg_ptr, length_ptr, ctr_ptr, ary_ptr)

def cu_generate_anchors(shifts, base_size, ratios, scales, feat_stride, anchors):
    K, A, N = anchors.shape
    scale_size = scales.shape[0]
    ratio_size = ratios.shape[0]
    cdef VALUE_TYPE * shifts_ptr = <VALUE_TYPE *><uintptr_t> shifts._ptr
    cdef VALUE_TYPE * ratios_ptr = <VALUE_TYPE *><uintptr_t> ratios._ptr
    cdef VALUE_TYPE * scales_ptr = <VALUE_TYPE *><uintptr_t> scales._ptr
    cdef VALUE_TYPE * anchors_ptr = <VALUE_TYPE *><uintptr_t> anchors._ptr
    thrust_generate_anchors(A, K, N, shifts_ptr, ratios_ptr, scales_ptr, ratio_size, scale_size, feat_stride, base_size, anchors_ptr)

def cu_get_ith_bbox(bbox, i, ary):
    N, M = bbox.shape
    cdef VALUE_TYPE * bbox_ptr = <VALUE_TYPE *><uintptr_t> bbox._ptr
    cdef VALUE_TYPE * ary_ptr = <VALUE_TYPE *><uintptr_t> ary._ptr
    thrust_get_ith_bbox(N, M, bbox_ptr, i, ary_ptr)

def cu_clip_roi(roi, start, end, step, min_v, max_v, ary):
    N, M = roi.shape
    cdef VALUE_TYPE * roi_ptr = <VALUE_TYPE *><uintptr_t> roi._ptr
    cdef VALUE_TYPE * ary_ptr = <VALUE_TYPE *><uintptr_t> ary._ptr
    thrust_clip_roi(N, M, roi_ptr, start, end, step, min_v, max_v, ary_ptr)
