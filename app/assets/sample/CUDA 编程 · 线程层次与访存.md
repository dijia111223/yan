---
title: CUDA 编程 · 线程层次与访存
created: 2026-09-12
updated: 2026-09-12
tags: [CUDA, 并行计算, 考研]
source: "《CUDA 编程：基础与实践》第 3 章 + 课程实验"
# lineage: 血缘字段预留，与知识库蓝图统一语料层规范对齐
# lineage:
#   derived_from: []
---

# CUDA 线程层次与访存

GPU 的性能上限**不在算力，在访存**。这一章把线程层次和内存层次绑在一起看。

## 一、线程层次

一个 kernel 启动时，线程被组织成三层：

| 层次 | 索引 | 作用域 | 共享内存可见性 |
| --- | --- | --- | --- |
| Thread | `threadIdx` | 单个线程 | 私有寄存器 |
| Block | `blockIdx` | 块内所有线程 | **块内共享** |
| Grid | `gridIdx` | 整个 kernel | 全局内存 |

关键结论：**同一个 block 内的线程才能通过 shared memory 通信**。跨 block 只能走全局内存，
延迟高一个数量级。

## 二、算全局索引

最常用的一维展开式（`blockDim.x` 是每块线程数）：

$$
\text{idx} = \text{blockIdx.x} \times \text{blockDim.x} + \text{threadIdx.x}
$$

二维时按行优先展开：

$$
\text{row} = \text{blockIdx.y} \times \text{blockDim.y} + \text{threadIdx.y}
$$

## 三、访存是瓶颈

矩阵乘法的算术强度约为 $O(n)$，而访存是 $O(n^2)$。所以优化方向永远是
**提高数据复用率**，而不是堆算力。

用 shared memory 分块（tiling）把全局访存降到原来的 $1/\text{TILE}$：

```cpp
#define TILE 32

__global__ void matmul_tiled(const float* A, const float* B, float* C, int n) {
    __shared__ float As[TILE][TILE];
    __shared__ float Bs[TILE][TILE];

    int tx = threadIdx.x, ty = threadIdx.y;
    int row = blockIdx.y * TILE + ty;
    int col = blockIdx.x * TILE + tx;
    float acc = 0.0f;

    for (int t = 0; t < n / TILE; ++t) {
        // 每个线程搬运一个元素到 shared memory
        As[ty][tx] = A[row * n + t * TILE + tx];
        Bs[ty][tx] = B[(t * TILE + ty) * n + col];
        __syncthreads();          // 必须同步，否则读到脏数据

        for (int k = 0; k < TILE; ++k)
            acc += As[ty][k] * Bs[k][tx];

        __syncthreads();          // 下一轮覆盖前再同步一次
    }
    C[row * n + col] = acc;
}
```

> `__syncthreads()` 放错位置是初学阶段最常见的错误：写完就覆盖，会读到别人的半成品。

## 四、用 Python 快速验证形状

调 kernel 之前先用小数组验证索引推导，比直接上 GPU 排错快得多：

```python
import numpy as np

def blocked_index(block_idx, block_dim, thread_idx):
    """复刻 kernel 里的全局索引展开，用来核对形状。"""
    return block_idx * block_dim + thread_idx

n, tile = 1024, 32
idx = [blocked_index(b, tile, t) for b in range(n // tile) for t in range(tile)]
assert sorted(idx) == list(range(n)), "索引没覆盖满，说明展开式错了"
print(f"覆盖 {len(idx)} 个元素，无重复无遗漏")
```

## 五、待办

- [x] 线程层次与索引展开
- [x] shared memory tiling
- [ ] 用 `nsight compute` 看实际占用率
- [ ] 对比 tiled / 非 tiled 的实测吞吐

## 相关笔记

- 上一节：[[CUDA 编程 · 第一个 kernel]]
- 下一节：[[CUDA 编程 · 归约与原子操作]]
- 参考：[CUDA C++ Programming Guide](https://docs.nvidia.com/cuda/cuda-c-programming-guide/)
