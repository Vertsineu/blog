#import "@hugo/templates:0.1.0": article
#import "@hugo/utils:0.1.0": *
#import "@preview/cetz:0.5.2"

#show: article.with(
  title: "算法讲解——寻找两个升序数组的中位数",
  date: datetime(year: 2026, month: 6, day: 25),
  tags: (
    domains: "algorithm",
    intents: "introduction",
  ),
  draft: false
)

= 前言

明天考试，但是实在没有复习的欲望，感觉丝毫没有前几天刷 leetcode 有意思，姑且就写一篇算法讲解的 blog，讲一下我觉得非常有意思的一道题：

#blockquote[
  给定两个大小分别为 $m$ 和 $n$ 的正序（从小到大）数组 $"nums1"$ 和 $"nums2"$。请你找出并返回这两个正序数组的中位数，算法的时间复杂度应该为 $O(log(m + n))$。
]

= 分析

看到有序 + $O(log n)$ 复杂度，显然这是一个二分查找的题，但是难点就在于这里同时有两个数组，如果先做归并（merge）再二分，时间复杂度一定是 $O(m + n)$ 的，所以我们必须在不合并的前提下同时对两个数组做二分查找。

而且，令总数组长度为 $n$，对于长度不同的数组，我们所要二分查找的数还不一样：

- 对于奇数长度的数组，我们仅需要查找 $floor(n / 2)$ 索引处的数即可。
- 对于偶数长度的数组，我们需要查找 $floor(n / 2) - 1$ 和 $floor(n / 2)$ 索引处的数相加除以 $2$。

= 思路

首先，我们可以抽象出一个过程（Procedure），给定两个有序数组，找到索引为 $k$ 的元素，函数原型类似于：

```cpp
int findKth(const std::vector<int>& nums1, const std::vector<int>& nums2, int k);
```

如果我们实现好了这个函数，那么我们最终的答案很简单的就是：

```cpp
class Solution {
public:
    double findMedianSortedArrays(std::vector<int>& nums1, std::vector<int>& nums2) {
        int m = nums1.size(), n = nums2.size();
        if ((m + n) % 2 == 0) {
            return (double) (
              findKth(nums1, nums2, (m + n) / 2 - 1) + 
              findKth(nums1, nums2, (m + n) / 2)
            ) / 2;
        } else {
            return findKth(nums1, nums2, (m + n) / 2);
        }
    }
};
```

因此接下来我们需要实现 `findKth` 这个函数。

然后，令这两个有序数组分别为 $a[0..m - 1]$ 和 $b[0..n - 1]$，归并后的数组为 $c[0..m + n - 1]$，并且不失一般性的，不妨设 $m <= n$，以便后续分析。

对于 $forall k in [0..n + m - 1] inter ZZ$，我们要找的数肯定要么位于 $a$，要么位于 $b$，要么作为重复元素同时位于 $a$ 和 $b$。不管怎样，我们都可以假设，在最后二分时，$a$ 左边取 $k_1$ 个数、$b$ 左边取 $k_2$ 个数，且这 $k$ 个数都不大于右边的候选值，于是有 $k_1 + k_2 = k$。

证明很简单，如果我们在 $c[k]$ 的左侧将合并后的数组 $c$ 切成两半，那么左边正好有 $k$ 个数。由于 $a$ 和 $b$ 各自有序，这个切分对应到两个数组中也一定是两个前缀，设这两个前缀长度分别为 $k_1$ 和 $k_2$，自然有 $k_1 + k_2 = k$。

举个例子，$a = [1, 3, 5], b = [2, 4, 6]$，我找的是 $k = 3$ 的元素，归并后找一下发现是 $4$ 这个数。在 $4$ 左侧，$a$ 贡献了 $[1, 3]$ 这 $k_1 = 2$ 个数，$b$ 贡献了 $[2]$ 这 $k_2 = 1$ 个数。因此有 $k_1 + k_2 = k$。

我们二分的时候所需要找的就是合适的 $k_1$ 和 $k_2$，正好对应着两个数组中位于 $c[k]$ 左侧的前缀长度，而 $k_1$ 或者 $k_2$ 所在索引处正好对应着我们需要的索引为 $k$ 的元素，即 $c[k] = min(a[k_1], b[k_2])$。

因此，一个初步的二分模板如下所示：

```cpp
int findKth(const std::vector<int>& nums1, const std::vector<int>& nums2, int k) {
  int m = nums1.size(), n = nums2.size();
  int l = std::max(0, k - n), r = std::min(m, k);
  while (l <= r) {
    int k1 = l + (r - l) / 2;
    int k2 = k - k1;

    // TODO
  }
}
```

其中 `k2` 由 `k1` 被 `k` 减去而得到，因此天然保证了 $k_1 + k_2 = k$ 的约束。

但是，我们怎么知道什么情况下 $k_1$ 和 $k_2$ 恰好是 $c[k]$ 左侧的前缀长度呢？这时候，我们就要思考一下如果恰好是的情况下，会有什么特性：

- 两数组有序，因此显然 $a[k_1 - 1] <= a[k_1]$ 且 $b[k_1 - 1] <= b[k_1]$。
- $c[k] = min(a[k_1], b[k_2])$，因此显然 $a[k_1] >= c[k]$ 且 $b[k_2] >= c[k]$。
  - $a[k_1] >= c[k]$，因此可证 $b[k_2] >= a[k_1 - 1]$，否则，如果 $b[k_2] < a[k_1 - 1]$，则有 $b[k_2] < a[k_1 - 1] <= a[k_1] = c[k]$，那么在 $b$ 中，比 $c[k]$ 小的数至少有 $k_2 + 1$ 个（从 $b[0]$ 到 $b[k_2]$），而在 $a$ 中，比 $c[k]$ 小的数有 $k_1$ 个（从 $a[0]$ 到 $a[k_2 - 1]$），因此在 $c$ 中，比 $c[k]$ 小的数至少有 $k_1 + k_2 + 1$ 个，但是 $k_1 + k_2 = k$，矛盾！
  - $b[k_2] >= c[k]$，同理可证 $a[k_1] >= b[k_2 - 1]$。

纯数学语言可能不是很直观，画出来就很直观了。

如果 $b[k_2] < a[k_1 - 1]$，那么这种错误情况下的*错误*排列如下所示：

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0, $a[k_1 - 1]$), (0.6, $a[k_1]$))
  let nb = ((-0.9, $b[k_2 - 1]$), (-0.3, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>

如果 $a[k_1] < b[k_2 - 1]$，那么这种错误情况下的*错误*排列如下所示：

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0.9, $a[k_1 - 1]$), (-0.3, $a[k_1]$))
  let nb = ((-0, $b[k_2 - 1]$), (0.6, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>


而 $k_1$ 和 $k_2$ 恰好是 $c[k]$ 左侧的前缀长度时，对应的 $a$ 和 $b$ 数组中元素的*正确*排列方式为：

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0.3, $a[k_1 - 1]$), (0.3, $a[k_1]$))
  let nb = ((-0.6, $b[k_2 - 1]$), (0, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>

其中 $b[k_2] = c[k]$，或者

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0.6, $a[k_1 - 1]$), (0, $a[k_1]$))
  let nb = ((-0.3, $b[k_2 - 1]$), (0.3, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>

其中 $a[k_1] = c[k]$，或者

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0.3, $a[k_1 - 1]$), (0.3, $a[k_1]$))
  let nb = ((-0.6, $b[k_2 - 1]$), (0.6, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>

其中 $a[k_1] = c[k]$，或者

#cetz.canvas(length: 3cm, {
  import cetz.draw: *

  let (beg, end) = (-1.5, 1.5);
  let ha = 0.3; let hb = 0;
  let off = 0.03;
  let na = ((-0.6, $a[k_1 - 1]$), (0.6, $a[k_1]$))
  let nb = ((-0.3, $b[k_2 - 1]$), (0.3, $b[k_2]$))

  // arrays
  content((beg - off * 2, ha), anchor: "east", $a$)
  line((beg, ha), (end, ha))
  content((beg - off * 2, 0), anchor: "east", $b$)
  line((beg, hb), (end, hb))

  for (x, ct) in na {
    line((x, ha + off), (x, ha - off))
    content((x, ha + off * 2), anchor: "south", ct)
  }

  for (x, ct) in nb {
    line((x, hb + off), (x, hb - off))
    content((x, hb - off * 2), anchor: "north", ct)
  }
}) <frame>

其中 $b[k_2] = c[k]$。

因此，在二分查找过程中，只要 $a[k_1 - 1] <= b[k_2]$ 且 $b[k_2 - 1] <= a[k_1]$，那么我们就找到了正确的 $k_1$ 和 $k_2$，这便是二分查找的退出条件。

而如果 $b[k_2] < a[k_1 - 1]$，那么说明 $k_2$ 太小了，而 $k_1$ 太大了；如果 $a[k_1] < b[k_2 - 1]$，那么说明 $k_1$ 太小了，而 $k_2$ 太大了，这便是二分查找缩小边界的规则。

因此，我们可以有如下实现：

```cpp
int findKth(const std::vector<int>& nums1, const std::vector<int>& nums2, int k) {
  int m = nums1.size(), n = nums2.size();
  int l = 0, r = m;
  while (l <= r) {
    int k1 = l + (r - l) / 2;
    int k2 = k - k1;

    int l1 = (k1 == 0) ? INT_MIN : nums1[k1 - 1];
    int r1 = (k1 == m) ? INT_MAX : nums1[k1];
    int l2 = (k2 == 0) ? INT_MIN : nums2[k2 - 1];
    int r2 = (k2 == n) ? INT_MAX : nums2[k2];

    if (l1 <= r2 && l2 <= r1) {
      return std::min(r1, r2);
    } else if (l1 > r2) {
      r = k1 - 1;
    } else {
      l = k1 + 1;
    }
  }

  return -1; // not found
}
```

工程上，因为可能会有数组越界的问题，所以如果遇到数组边界，我们就将边界设置为 `INT_MIN` 和 `INT_MAX`。同时，`k1` 的二分范围要限制在 $max(0, k - n)..min(m, k)$ 内，这样才能保证 `k2` 始终落在 $0..n$ 内。

综上，这题的一种解法如下所示：

```cpp
class Solution {
public:
  double findMedianSortedArrays(std::vector<int>& nums1, std::vector<int>& nums2) {
    if (nums1.size() > nums2.size()) {
      return findMedianSortedArrays(nums2, nums1);
    }

    int m = nums1.size(), n = nums2.size();
    if ((m + n) % 2 == 0) {
      return (double) (
        findKth(nums1, nums2, (m + n) / 2 - 1) + 
        findKth(nums1, nums2, (m + n) / 2)
      ) / 2;
    } else {
      return findKth(nums1, nums2, (m + n) / 2);
    }
  }
private:
  int findKth(const std::vector<int>& nums1, const std::vector<int>& nums2, int k) {
    int m = nums1.size(), n = nums2.size();
    int l = 0, r = m;
    while (l <= r) {
      int k1 = l + (r - l) / 2;
      int k2 = k - k1;

      int l1 = (k1 == 0) ? INT_MIN : nums1[k1 - 1];
      int r1 = (k1 == m) ? INT_MAX : nums1[k1];
      int l2 = (k2 == 0) ? INT_MIN : nums2[k2 - 1];
      int r2 = (k2 == n) ? INT_MAX : nums2[k2];

      if (l1 <= r2 && l2 <= r1) {
        return std::min(r1, r2);
      } else if (l1 > r2) {
        r = k1 - 1;
      } else {
        l = k1 + 1;
      }
    }
    return -1;
  }
};
```

其中，为了防止 `k2` 数组越界过多，所以 `nums1` 的长度需要小于等于 `nums2` 的长度，也就是 $m <= n$。

= 优化

其实，在这种解法之上，我们还可以再做一些优化，让 `findKth` 只需要调用一次！

注意到，我们在使用二分查找的时候，额外选用的是 $k_1 - 1$ 和 $k_2 - 1$ 这两个左边的索引，那么显然，如果我用 $k_1 + 1$ 和 $k_2 + 1$ 这两个右边的索引，然后把函数里面对应的符号修改一下，是不是也是一样的能够实现 `findKth` 函数？

再进一步，实际上 `findKth` 函数不仅找到了索引为 $k$ 的数，同时还找到了索引为 $k - 1$ 的数！即，$c[k] = min(a[k_1], b[k_2])$，且 $c[k - 1] = max(a[k_1 - 1], b[k_2 - 1])$！

证明也不难，把之前列举的那几种 $a[k_1 - 1..k_1]$ 和 $b[k_2 - 1..k_2]$ 的相对位置的情况全都重写一遍就结束了。

因此，优化后的解法如下所示：

```cpp
class Solution {
public:
  double findMedianSortedArrays(std::vector<int>& nums1, std::vector<int>& nums2) {
    if (nums1.size() > nums2.size()) {
      return findMedianSortedArrays(nums2, nums1);
    }

    int m = nums1.size(), n = nums2.size();
    int l = 0, r = nums1.size();

    while (l <= r) {
      int mid1 = l + (r - l) / 2;
      int mid2 = (m + n + 1) / 2 - mid1;

      int l1 = (mid1 == 0) ? INT_MIN : nums1[mid1 - 1];
      int r1 = (mid1 == m) ? INT_MAX : nums1[mid1];
      int l2 = (mid2 == 0) ? INT_MIN : nums2[mid2 - 1];
      int r2 = (mid2 == n) ? INT_MAX : nums2[mid2];

      if (l1 <= r2 && l2 <= r1) {
        if ((m + n) % 2 == 0) {
          return (double) (std::max(l1, l2) + std::min(r1, r2)) / 2;
        } else {
          return std::max(l1, l2);
        }
      } else if (l1 > r2) {
        r = mid1 - 1;
      } else {
        l = mid1 + 1;
      }
    }

    return -1; // not found
  }
};
```

其中，我们令 $k = (m + n + 1) / 2$，对于偶数长度的数组来说，$k = floor((m + n) / 2)$，而 $k - 1 = floor((m + n) / 2) - 1$，正好是求中位数所需的两个数；对于奇数长度的数组来说，$k = floor((m + n) / 2) + 1$，而 $k - 1 = floor((m + n) / 2)$，后者是我们求中位数所需的那个数。因此，不论是偶数还是奇数长度，我们都可以在一次二分查找中全部找到所需的数。

= 结语

这是一道非常经典并且有趣的二分查找的困难题，很久之前就在我校《算法基础》课程的考试中出现过，当时我实在没想出来有什么好的解法，直到最近刷 leetcode 才想到如此优雅高效并且易于理解的好方法，希望能帮助读者更好吃透这道优秀的题目。
