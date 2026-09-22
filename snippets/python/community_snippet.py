# 社区贡献：列表去重保序（by c991china）
def dedupe(seq):
    seen = set()
    return [x for x in seq if not (x in seen or seen.add(x))]


if __name__ == '__main__':
    print(dedupe([1, 2, 2, 3, 1]))
