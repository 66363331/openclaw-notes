#!/usr/bin/env python3
"""
数脉API - 手机号码空号检测（号段版）
从文件读取号段（7-8位），每个号段取第一個完整号码来检测
"""
import urllib.request
import json
import time
import random
import sys

# 凭证
APPCODE = "fa159e4ba4a14c8682bceafb219d3da1"
API_URL = "https://mobileempty.shumaidata.com/mobileempty"

STATUS_MAP = {
    1: "实号（正常在用）",
    2: "空号（已停机/销号）",
    3: "停机",
    4: "库无（不在数据库）",
    5: "沉默号",
    6: "风险号",
    0: "未知",
}

def expand_segment(seg):
    """把7-8位号段转成11位完整号码（取0000）"""
    seg = seg.strip()
    if len(seg) == 7:
        return seg + "0000"
    elif len(seg) == 8:
        return seg + "000"
    else:
        return None

def check_phone(mobile):
    try:
        req = urllib.request.Request(
            f"{API_URL}?mobile={mobile}",
            headers={
                "Authorization": f"APPCODE {APPCODE}",
                "Content-Type": "application/json"
            },
            method="GET"
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode())
            return data
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}"}
    except Exception as e:
        return {"error": str(e)}

def main():
    segment_file = "/home/lilei/.openclaw/workspace/phones_to_check.txt"
    max_check = 100  # 免费额度100个

    with open(segment_file, "r") as f:
        raw = f.read()

    import re
    segments = re.findall(r'\b(\d{7,8})\b', raw)
    segments = sorted(set(segments))
    print(f"共读取 {len(segments)} 个号段")

    # 随机取最多max_check个
    if len(segments) > max_check:
        sample = random.sample(segments, max_check)
    else:
        sample = segments

    phones = []
    for seg in sample:
        phone = expand_segment(seg)
        if phone:
            phones.append((seg, phone))

    print(f"开始检测 {len(phones)} 个号码...")
    print("-" * 60)

    results = {1: [], 2: [], 3: [], 4: [], 5: [], 6: [], 0: [], "error": []}

    for i, (seg, phone) in enumerate(phones, 1):
        res = check_phone(phone)
        if "error" in res:
            results["error"].append((seg, phone, res["error"]))
            status_name = f"错误({res['error']})"
        elif res.get("code") == 200:
            data = res.get("data", {})
            status_code = data.get("status", 0)
            if status_code in results:
                results[status_code].append((seg, phone, data))
            else:
                results[0].append((seg, phone, data))
            status_name = STATUS_MAP.get(status_code, f"未知({status_code})")
        else:
            results["error"].append((seg, phone, res))
            status_name = f"API错误(code={res.get('code')})"

        print(f"[{i}/{len(phones)}] {phone} -> {status_name}")

        if i < len(phones):
            time.sleep(1.1)  # 限速，避免触发风控

    # 汇总
    print("\n" + "=" * 60)
    print("📊 检测结果汇总")
    print("=" * 60)
    total_valid = 0
    for k in [1, 2, 3, 4, 5, 6, 0]:
        if results[k]:
            print(f"  {STATUS_MAP.get(k, k)}: {len(results[k])} 个")
            total_valid += len(results[k])
    if results["error"]:
        print(f"  错误/异常: {len(results['error'])} 个")

    # 保存结果
    save_path = "/home/lilei/.openclaw/workspace/phone_check_results.json"
    with open(save_path, "w", encoding="utf-8") as f:
        json.dump({k: [(a, b, str(c)) for a, b, c in v] for k, v in results.items()}, f, ensure_ascii=False, indent=2)
    print(f"\n结果已保存: {save_path}")

if __name__ == "__main__":
    main()
