# The --n-cpu-moe and -cmoe cells are not the model

## The symptom

The placement sweep put four cells on the 35B that are 34x to 71x faster than the
one-device cell:

| cell | decode tok/s | prompt eval tok/s |
|---|---|---|
| one-device (the reference) | 0.1450 | 6.4086 |
| two-ncpumoe16 | 5.9683 | 15.9140 |
| two-ncpumoe24 | 6.8473 | 19.0095 |
| two-ncpumoe32 | 10.3336 | 42.7350 |
| two-cmoe | 9.8263 | 36.2357 |

None of them is the model. The output starts right and then collapses into repeated junk
tokens.

## The reference

The same model, the same prompt, everything on the CPU (`-ngl 0`), 400 generated tokens,
11.0374 tok/s, 1675 characters, no junk characters in the whole answer:

> A binary search tree (BST) is a data structure that organizes data in a hierarchical
> manner, where each node has at most two children, referred to as the left child and the
> right child. It's called a "search tree" because its structure enables efficient searching,
> insertion, and deletion of values.
>
> **Core Property:** The defining rule of a BST is the **binary search property**: for any
> given node, all values in its left subtree are strictly less than the node's value, and
> all values in its right subtree are strictly greater. This property must hold recursively
> for every node in the tree.
>
> **Structure/Terminology:**
>
> - Root: topmost node
> - Internal nodes: have children
> - Leaves: nodes with no children
> - Subtree: ...

## The broken cells

`-cmoe`, same model, same prompt, 400 generated tokens, 10.2745 tok/s, 915 characters of
which **265 are CJK characters that are not in the prompt**, and the tail is one token
repeated:

> ... The time complexity of searching in a binary search tree depends on the height of the
> tree. In the best case, when the tree is perfectly balanced, the height is
> \(彩彩ihtkapicode者可thetic者可 Im Imothe彩可omor可可可可可ør可可可可可可可可可可可可可可可可可可可可可可...

`--n-cpu-moe 16`, same model, same prompt, 400 generated tokens, 6.1127 tok/s, 1914
characters, and the tail is another token repeated:

> ... ImicodeableObjectør ImicodeableObjectør ImicodeableObjectør ImicodeableObjectør ...

`--n-cpu-moe 32` degenerates the same way.

The first 24 tokens of every broken cell are the same as the GPU cells' first 24 tokens,
which is why the collapse is not visible in a short completion: the model is right for a
while and then stops being the model.

## What this means for the numbers

The broken cells are the fastest in the sweep, and that is the point. A cell that does not
compute the model does not pay for the model. Their throughput is not a placement of the
35B, so their numbers are not quotable as one, and the placement matrix
(`the-35b-placement-matrix-2026-10-20.md`) records them only so that nobody rediscovers
them and reads them as a result.

## What is not established

- The mechanism is not identified here. The cells keep the expert weights in the host and
  let the rest of the model onto the cards, and the output degenerates; whether the gather,
  the dequantisation, the split of the expert matmul, or the device boundary is at fault is
  a separate question, tracked in ticket 66.
- Only this model was tried. The 8B dense model has no experts to move, and the flag has
  nothing to move.
