import contextlib
from renom import precision
import collections
from renom.core import Node, Variable
from renom.cuda import is_cuda_active, has_cuda
if has_cuda():
    from renom.cuda.gpuvalue import GPUValue, get_gpu
import numpy as np


class Grads:
    '''This class contains gradients of each Node object.

    When the function ``grad`` which is a method of Node class is called,
    an instance of Grads class will be returned.

    For getting the gradient with respect to any Variable object 'x' which is on a
    computational graph, call the 'get' function of Grads object.

    Args:
        root(Node): Root node of the computational graph.
        weight_decay(float): Weight decay coefficient.


    Example:
        >>> import numpy as np
        >>> import renom as rm
        >>> a = rm.Variable(np.random.rand(2, 3))
        >>> b = rm.Variable(np.random.rand(2, 3))
        >>> c = rm.sum(a + 2*b)
        >>> grad = c.grad()
        >>> grad.get(a)   # Getting gradient of a.
        Mul([[ 1.,  1.,  1.],
             [ 1.,  1.,  1.]], dtype=float32)
        >>> grad.get(b)
        RMul([[ 2.,  2.,  2.],
              [ 2.,  2.,  2.]], dtype=float32)
    '''

    def __init__(self, root=None, weight_decay=None):
        self.stroage = {}
        self.variables = {}
        self._auto_updates = []
        self._weight_decay = weight_decay

        if root is not None:
            self._build_refcounts(root)

    def _build_refcounts(self, root):
        self._refcounts = collections.Counter()
        self._backwards = collections.Counter()

        q = collections.deque([root])

        while q:
            t = q.pop()
            if isinstance(t, Node):
                nodeid = id(t)
                if isinstance(t, Variable):
                    self.check_weight_decay(t)
                seen = nodeid in self._refcounts
                self._refcounts[nodeid] += 1

                if not seen and not getattr(t, '_no_backward', False):
                    for c in t._args:
                        q.append(c)

    def check_weight_decay(self, node):
        if node.weight_decay is not None:
            wd = node.weight_decay or self._weight_decay
            if wd is not None and wd != 0:
                self.variables[id(node)] = wd * node

    @contextlib.contextmanager
    def unlock_node(self, node):
        if hasattr(node, 'setflags') and not node.flags.writeable:
            node.setflags(write=True)
            yield
            node.setflags(write=False)
        else:
            yield

    def store(self, node, dy):
        selfid = id(node)
        self.stroage[selfid] = Node(dy)  # if cuda active, dy must be GPUValue type.

    def restore(self, node, default=None):
        selfid = id(node)
        return self.stroage.get(selfid, default)

    def add(self, node, dy, caller=None):
        '''This method stores given gradient ``dy`` to the dictionary with a key which is
        the id of given node object.

        Args:
            node (Node): Node object whose gradient should be given as dy.
            dy (Node, ndarray): Gradient related to the argument node.
            caller (function): **deprecated**
        '''
        selfid = id(node)
        if selfid in self.variables:
            v = self.variables[selfid]
            with self.unlock_node(v):
                if has_cuda() and isinstance(dy, GPUValue):
                    diff = v.get_gpu() + dy
                    v.set_gpu(diff)
                else:
                    v[...] += dy
        else:
            if has_cuda() and isinstance(dy, GPUValue):
                dy = Variable(dy)
            self.variables[selfid] = dy
            if node._auto_update:
                self._auto_updates.append(node)

        self._backwards[selfid] += 1

        return self._refcounts[selfid] <= self._backwards[selfid]

    _omit = object()

    def get(self, node, default=_omit):
        '''This function returns the gradient with respect to the given node.
        In the case of that there is no gradient of given node, this function
        returns given object as ``default``. If nothing is set to default and
        no gradient is found, this function raises an error.

        Args:
            node (Node): Returns a gradient with respect to this argument.
            default (object): If gradient of given node is not found, object given to this
                argument will be returned.

        Return:
            (ndarray, Node, None, object): Gradient of given node object or object given to argument default.
        '''
        if default is self._omit:
            try:
                return self.variables[id(node)]
            except KeyError:
                raise Exception(
                    'Node not found. Ensure that _update_diff was properly called on the node first.')
        else:
            return self.variables.get(id(node), default)

    def set(self, node, diff):
        '''This function will set a gradient to the dictionary using id of
        given node object as a key.

        Args:
            node (Node): Node object whose gradient should be given as dy.
            dy (Node, ndarray): Gradient related to the argument node.
        '''
        self.variables[id(node)] = diff

    def update_node(self, node, opt=None):
        import time
        if node.prevent_update:
            return

        with self.unlock_node(node):
            dy = self.get(node) if opt is None else opt(self.get(node), node)
            if node._auto_update:
                if callable(node.auto_update):
                    node.auto_update(dy)
                else:
                    if is_cuda_active():
                        ngpu = get_gpu(node)
                        ngpu -= get_gpu(dy)
                    else:
                        node[...] -= dy
            node.detach_graph()

    def update(self, opt=None, models=()):
        '''This function updates variable objects on the computational graph
        using obtained gradients.

        If an optimizer instance is given, gradients are rescaled
        with regard to the optimization algorithm before updating.

        Args:
            opt (Optimizer): Algorithm for rescaling gradients.
            models: List of models to update variables. When specified,
                    variables which does not belong to one of the models
                    are not updated.

        Example:
            >>> import numpy as np
            >>> import renom as rm
            >>> a = rm.Variable(np.arange(4).reshape(2, 2))
            >>> b = rm.Variable(np.arange(4).reshape(2, 2))
            >>> print('Before', a)
            Before
             [[ 0.  1.]
             [ 2.  3.]]
            >>> out = rm.sum(2*a + 3*b)
            >>> grad = out.grad(models=(a, ))
            >>> print('Gradient', grad.get(a))
            Gradient
             [[ 2.  2.]
             [ 2.  2.]]
            >>> grad.update()
            >>> print('Updated', a)
            Updated
             [[-2. -1.]
             [ 0.  1.]]

        '''

        if not models:
            for node in self._auto_updates:
                self.update_node(node, opt)
        else:
            for model in models:
                for node in model.params.values():
                    if id(node) in self.variables:
                        self.update_node(node, opt)

    def clip_gradient(self, threshold=0.5, norm=2):
        '''This function clips the gradient if gradient is above threshold.

        Args:
            gradient: gradient object
            threshold(float): theshold
            norm(int): norm of gradient

        Examples:
            >>> from **** import gradient_clipping
            >>>
            >>> grad = loss.grad()
            >>> gradient_clipping(grad, threshold=0.5)
            >>>
            >>> grad.update(Sgd(lr=0.01))

        '''

        # setting variables etc.
        variables = self.variables
        if len(variables) == 0:
            return
        norm = float(norm)
        threshold = float(threshold)

        if norm == float('inf'):
            # h infinity
            total_norm = np.max([i for i in variables.values()])
        else:
            # regular norm
            total_norm = 0
            for i in variables:
                arr = variables[i] ** norm
                total_norm += rm.sum(arr)
            total_norm = total_norm ** (1 / total_norm)

        # process gradient
        if threshold < total_norm:
            for i in variables:
                variables[i] = threshold * variables[i] / (total_norm + 1e-6)


def _grad(self, initial=None, detach_graph=True, weight_decay=None, **kwargs):
    '''This method follows computational graph and returns the gradients of
    Variable object.

    Args:
        initial (ndarray): Initial value of following the graph.
        detach_graph (bool): If it's True, the computational graph will be destroyed.
        weight_decay (float): Sets the default weight decay of the model.
                            See the Variable class for more info.
    '''
    if not self._has_autoupdate():
        return Grads()

    if initial is None:
        if self.size > 1:
            raise ValueError('Initial diff is required for scalar value.')

        if is_cuda_active():
            initial = Node(get_gpu(self).ones_like_me())
        else:
            initial = np.ones_like(self).astype(precision)

    context = Grads(self, weight_decay=weight_decay)
    self._update_diff(context, initial, **kwargs)

    if detach_graph:
        self.detach_graph()
    return context


Node.grad = _grad
