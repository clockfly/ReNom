import contextlib
import bisect
cimport numpy as np
import numpy as pnp
from cuda_base import *
cimport cython
from numbers import Number
from libc.stdlib cimport malloc, free
from libc.stdint cimport uintptr_t
from libc.string cimport memcpy
from cuda_utils cimport _VoidPtr
from renom.config import precision
import collections
import renom.core
import renom.cuda

def cuMalloc(uintptr_t nbytes):
    cdef void * p
    runtime_check(cudaMalloc( & p, nbytes))
    return < uintptr_t > p


def cuMemset(uintptr_t ptr, int value, size_t size):
    p = <void * >ptr
    runtime_check(cudaMemset(p, value, size))
    return

# Global C-defined variables cannot be accessed from Python
cdef void * ptrA, * ptrB # TODO: This is not a good solution. Change to pointer of arrays instead.
cdef cudaEvent_t eventA, eventB # Similar to above
cdef size_t pin_size = 0 # Make size always word-sized for increased performance in memcpy
cdef bint usingA = True # Used for switching between different pinned memory spaces when sending
cdef char toUse = '0' # Used for same purpose as above, inevitably useless but currently used in a bad implementation


# This function initiates the pinned memory space based on a sample batch
# This should be called before trying to pin memory
def initPinnedMemory(np.ndarray batch_arr):
    global pin_size, eventA, eventB, ptrA, ptrB
    if pin_size is not 0:
      freePinnedMemory()
    pin_size = <size_t> batch_arr.descr.itemsize*len(batch_arr)
    runtime_check(cudaMallocHost(&ptrA,pin_size))
    runtime_check(cudaMallocHost(&ptrB,pin_size))
    runtime_check(cudaEventCreate(&eventA))
    runtime_check(cudaEventCreate(&eventB))

# Pointless right now, as the user closing the program
# will always free up the allocated memory anyway
def freePinnedMemory():
    global ptrA, ptrB, pin_size
    cudaFreeHost(ptrA)
    cudaFreeHost(ptrB)
    pin_size = 0

# This function will accept a numpy array and move its data to the spaces
# previously allocated using initPinnedMemory.
def pinNumpy(np.ndarray arr):
    assert arr.descr.itemsize*len(arr) <= pin_size, "Attempting to insert memory larger than what was made available through initPinnedMemory.\n(Allocated,Requested)({:d},{:d})".format(pin_size,arr.descr.itemsize*len(arr))
    cdef void * vptr = <void*> arr.data
    cdef bin
    global usingA, ptrA, ptrB, toUse, eventA, eventB
    if usingA:
      # If we are currently trying to copy host data to the device given
      # space reserved in ptrA, wait until this transfer is finished
      cudaEventSynchronize(eventA)
      memcpy(ptrA, vptr, pin_size)
      usingA = False
      toUse = 'A'
      return
    else:
      # Same check as for ptrA
      cudaEventSynchronize(eventB)
      memcpy(ptrB, vptr, pin_size)
      usingA = True
      toUse = 'B'
      return
    return

def cuCreateStream(name = None):
    cdef cudaStream_t stream
    cdef char* cname
    runtime_check(cudaStreamCreate( & stream))
    if name is not None:
      py_byte_string = name.encode("UTF-8")
      cname = py_byte_string
      nvtxNameCudaStreamA(stream, cname)
    return < uintptr_t > stream


def cuSetDevice(int dev):
    runtime_check(cudaSetDevice(dev))
    return

def cuGetDevice():
    cdef int dev
    runtime_check(cudaGetDevice(&dev))
    return dev

def cuDeviceSynchronize():
    runtime_check(cudaDeviceSynchronize())


def cuCreateCtx(device=0):
    cdef CUcontext ctx
    driver_check(cuCtxCreate( & ctx, 0, device))
    return int(ctx)


def cuGetDeviceCxt():
    cdef CUdevice device
    driver_check(cuCtxGetDevice( & device))
    return int(device)


def cuGetDeviceCount():
    cdef int count
    runtime_check(cudaGetDeviceCount( & count))
    return int(count)


def cuGetDeviceProperty(device):
    cdef cudaDeviceProp property
    runtime_check(cudaGetDeviceProperties( & property, device))
    property_dict = {
        "name": property.name,
        "totalGlobalMem": property.totalGlobalMem,
        "sharedMemPerBlock": property.sharedMemPerBlock,
        "regsPerBlock": property.regsPerBlock,
        "warpSize": property.warpSize,
        "memPitch": property.memPitch,
        "maxThreadsPerBlock": property.maxThreadsPerBlock,
        "maxThreadsDim": property.maxThreadsDim,
        "maxGridSize": property.maxGridSize,
        "totalConstMem": property.totalConstMem,
        "major": property.major,
        "minor": property.minor,
        "clockRate": property.clockRate,
        "textureAlignment": property.textureAlignment,
        "deviceOverlap": property.deviceOverlap,
        "multiProcessorCount": property.multiProcessorCount,
        "kernelExecTimeoutEnabled": property.kernelExecTimeoutEnabled,
        "computeMode": property.computeMode,
        "concurrentKernels": property.concurrentKernels,
        "ECCEnabled": property.ECCEnabled,
        "pciBusID": property.pciBusID,
        "pciDeviceID": property.pciDeviceID,
        "tccDriver": property.tccDriver,
    }

    return property_dict


def cuFree(uintptr_t ptr):
    p = <void * >ptr
    runtime_check(cudaFree(p))
    return

# cuda runtime check
def runtime_check(error):
    if error != cudaSuccess:
        error_msg = cudaGetErrorString(error)
        raise Exception("CUDA Error: {}".format(error_msg))
    return

# cuda runtime check
def driver_check(error):
    cdef char * string
    if error != 0:
        cuGetErrorString(error, < const char**> & string)
        error_msg = str(string)
        raise Exception(error_msg)
    return

# Memcpy
# TODO: in memcpy function, dest arguments MUST come first!

cdef void cuMemcpyH2D(void* cpu_ptr, uintptr_t gpu_ptr, int size):
    # cpu to gpu
    runtime_check(cudaMemcpy(<void *>gpu_ptr, cpu_ptr, size, cudaMemcpyHostToDevice))
    return


cdef cuMemcpyD2H(uintptr_t gpu_ptr, void *cpu_ptr, int size):
    # gpu to cpu
    runtime_check(cudaMemcpy(cpu_ptr, <void *>gpu_ptr, size, cudaMemcpyDeviceToHost))
    return


def cuMemcpyD2D(uintptr_t gpu_ptr1, uintptr_t gpu_ptr2, int size):
    # gpu to gpu
    runtime_check(cudaMemcpy(< void*>gpu_ptr2, < const void*>gpu_ptr1, size, cudaMemcpyDeviceToDevice))
    return

cdef void cuMemcpyH2DAsync(void* cpu_ptr, uintptr_t gpu_ptr, int size, uintptr_t stream):
    # cpu to gpu
    global ptrA, ptrB, toUse
    if toUse is 'A':
      cpu_ptr = ptrA
    elif toUse is 'B':
      cpu_ptr = ptrB
    runtime_check(cudaMemcpyAsync(<void *>gpu_ptr, cpu_ptr, size, cudaMemcpyHostToDevice, <cudaStream_t> stream))
    if toUse is 'A':
      cudaEventRecord(eventA, <cudaStream_t> stream)
    elif toUse is 'B':
      cudaEventRecord(eventB, <cudaStream_t> stream)
    return


def cuMemcpyD2HAsync(uintptr_t gpu_ptr, np.ndarray[float, ndim=1, mode="c"] cpu_ptr, int size, int stream=0):
    # gpu to cpu
    runtime_check(cudaMemcpyAsync( & cpu_ptr[0], < const void*>gpu_ptr, size, cudaMemcpyDeviceToHost, < cudaStream_t > stream))
    return


def cuMemcpyD2DAsync(uintptr_t gpu_ptr1, uintptr_t gpu_ptr2, int size, int stream=0):
    # gpu to gpu
    runtime_check(cudaMemcpyAsync( < void*>gpu_ptr2, < const void*>gpu_ptr1, size, cudaMemcpyDeviceToDevice, < cudaStream_t > stream))
    return

def check_heap_device(*heaps):
    devices = {h._ptr.device_id for h in heaps if isinstance(h, renom.core.GPUValue)}

    current = {cuGetDevice()}
    if devices != current:
        raise RuntimeError('Invalid device_id: %s currennt: %s' % (devices, current))

class GPUHeap(object):
    def __init__(self, nbytes, ptr, device_id, stream=0):
        self.ptr = ptr
        self.nbytes = nbytes
        self.available = False
        self.device_id = device_id
        # The stream is decided by the allocator and given to all subsequently
        # constructed GPUHeaps. All Memcpy operations will occur on the same
        # stream.
        self._mystream = stream

    def __int__(self):
        return self.ptr

    def memcpyH2D(self, cpu_ptr, nbytes):
        # todo: this copy is not necessary
        buf = cpu_ptr.ravel()
        cdef _VoidPtr ptr = _VoidPtr(buf)

        with renom.cuda.use_device(self.device_id):
            # Async can be called safely, since if the user does not
            # set up all the requirements for Async, it will perform
            # as an ordinairy blocking call
            cuMemcpyH2DAsync(ptr.ptr, self.ptr, nbytes, self._mystream)

    def memcpyD2H(self, cpu_ptr, nbytes):
        shape = cpu_ptr.shape
        cpu_ptr = pnp.reshape(cpu_ptr, -1)

        cdef _VoidPtr ptr = _VoidPtr(cpu_ptr)

        with renom.cuda.use_device(self.device_id):
            cuMemcpyD2H(self.ptr, ptr.ptr, nbytes)

        pnp.reshape(cpu_ptr, shape)

    def memcpyD2D(self, gpu_ptr, nbytes):
        assert self.device_id == gpu_ptr.device_id
        with renom.cuda.use_device(self.device_id):
            cuMemcpyD2D(self.ptr, gpu_ptr.ptr, nbytes)

    def copy_from(self, other, nbytes):
        cdef void *buf
        cdef int ret
        cdef uintptr_t src, dest

        assert nbytes <= self.nbytes
        assert nbytes <= other.nbytes

        n = min(self.nbytes, other.nbytes)
        if self.device_id == other.device_id:
            # self.memcpyD2D(other, n)
            other.memcpyD2D(self, n)
        else:
            runtime_check(cudaDeviceCanAccessPeer(&ret, self.device_id, other.device_id))
            if ret:
                src = other.ptr
                dest = self.ptr
                runtime_check(cudaMemcpyPeer(<void *>dest, self.device_id, <void*>src, other.device_id, nbytes))
            else:
                buf = malloc(n)
                if not buf:
                    raise MemoryError()
                try:
                    with renom.cuda.use_device(other.device_id):
                        cuMemcpyD2H(other.ptr, buf, n)

                    with renom.cuda.use_device(self.device_id):
                        cuMemcpyH2D(buf, self.ptr, n)

                finally:
                    free(buf)

    def free(self):
        with renom.cuda.use_device(self.device_id):
            cuFree(self.ptr)

class allocator(object):

    def __init__(self):
        self._pool_lists = collections.defaultdict(list)
        # We create one stream for all the GPUHeaps to share
        self._memsync_stream = cuCreateStream("Memcpy Stream")

    @property
    def pool_list(self):
        device = cuGetDevice()
        return self._pool_lists[device]

    def malloc(self, nbytes):
        pool = self.getAvailablePool(nbytes)
        if pool is None:
            ptr = cuMalloc(nbytes)
            pool = GPUHeap(nbytes=nbytes, ptr=ptr, device_id=cuGetDevice(), stream=self._memsync_stream)
        return pool

    def free(self, pool):
        pool.available = True
        device_id = pool.device_id
        index = bisect.bisect(self._pool_lists[device_id], (pool.nbytes,))
        self._pool_lists[device_id].insert(index, (pool.nbytes, pool))

    def getAvailablePool(self, size):
        pool = None
        min = size
        max = size * 2 + 4096

        device = cuGetDevice()
        pools = self._pool_lists[device]

        idx = bisect.bisect_left(pools, (size,))

        for i in range(idx, len(pools)):
            _, p = pools[i]
            if p.nbytes >= max:
                break

            if min <= p.nbytes:
                pool = p
                pool.available = False
                del pools[i]
                break

        return pool

    def release_pool(self, deviceID=None):

        def release(pool_list):
            available_pools = [p for p in pool_list if p[1].available]
            for p in available_pools:
                p[1].free()
                pool_list.remove(p)

        if deviceID is None:
            for d_id, pools in self._pool_lists.items():
                release(pools)
        else:
            release(self._pool_lists[deviceID])


gpu_allocator = allocator()

def _cuSetLimit(limit, value):
    cdef size_t c_value=999;

    cuInit(0)

    ret = cuCtxGetLimit(&c_value, limit)
    print(ret, c_value)

    cuCtxSetLimit(limit, value)
    print(value)
