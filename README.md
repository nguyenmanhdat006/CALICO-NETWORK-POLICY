# LAB: NetworkPolicy với 2 Pod và lệnh ping

Mục tiêu: dùng **đúng một lệnh ping** để thấy tận mắt từng quy tắc của NetworkPolicy:
default deny ingress, default deny egress (chừa DNS), mở một chiều,
quy tắc "mở một đường đi phải dán HAI tờ giấy", và bài học "mất DNS".

Mọi lệnh chạy trên **k8s-cp**, trong thư mục `ping-lab`.

---

## Cấu trúc thư mục

```
ping-lab/
├── README.md                              ← file này
├── 00-setup/
│   ├── 00-namespace.yaml                  ← tạo namespace ping-lab
│   ├── 01-pod-a.yaml                      ← Pod A (container busybox), nhãn app=pod-a
│   ├── 02-pod-b.yaml                      ← Pod B (container busybox), nhãn app=pod-b
│   └── 03-names.yaml                      ← cho 2 Pod có TÊN DNS (để ping bằng tên)
├── 01-ingress/                            ← giấy dán MẶT NGOÀI cửa (ai được VÀO)
│   ├── 10-default-deny-ingress.yaml
│   ├── 11-allow-ingress-a-to-b.yaml
│   └── 12-allow-ingress-b-to-a.yaml
├── 02-egress/                             ← giấy dán MẶT TRONG cửa (được đi RA tới đâu)
│   ├── 20-default-deny-egress.yaml        ← chặn hết chiều ra, CHỪA DNS
│   ├── 21-allow-egress-a-to-b.yaml
│   └── 22-allow-egress-b-to-a.yaml
├── 99-thi-nghiem/
│   └── default-deny-egress-no-dns.yaml    ← thí nghiệm "mất DNS"
├── test.sh                                ← chạy 6 phép thử, in bảng ✔/⛔
├── reset-policies.sh                      ← gỡ mọi policy, giữ Pod (để làm lại)
└── cleanup.sh                             ← xóa toàn bộ lab
```

## 6 phép thử mà `test.sh` chạy

| STT | Phép thử | Lệnh thực tế bên trong |
|---|---|---|
| 1 | A ping B (bằng IP) | `kubectl exec pod-a -- ping -c 1 <IP B>` |
| 2 | B ping A (bằng IP) | `kubectl exec pod-b -- ping -c 1 <IP A>` |
| 3 | A ping B (bằng TÊN) | `kubectl exec pod-a -- ping -c 1 pod-b` |
| 4 | A hỏi DNS | `kubectl exec pod-a -- nslookup pod-b` |
| 5 | A ping Internet | `kubectl exec pod-a -- ping -c 1 1.1.1.1` |
| 6 | B ping Internet | `kubectl exec pod-b -- ping -c 1 1.1.1.1` |

Bạn có thể tự gõ từng lệnh trên thay vì dùng `test.sh`. Script chỉ giúp đỡ phải gõ nhiều.

> **Lưu ý về ping:** ping dùng giao thức **ICMP**. NetworkPolicy chỉ ghi được cổng cho
> TCP/UDP/SCTP. Vì vậy các giấy phép A↔B trong lab **không ghi `ports`**, nghĩa là cho
> **mọi giao thức**, kể cả ICMP. Nếu một giấy phép có `ports: TCP 80` thì ping sẽ bị chặn.

---

## BƯỚC 0. Chuẩn bị

```bash
# Chép thư mục ping-lab lên k8s-cp (từ máy của bạn), ví dụ:
#   scp -r ping-lab <user>@192.168.56.10:~/
cd ~/ping-lab
chmod +x *.sh

kubectl apply -f 00-setup/00-namespace.yaml
kubectl apply -f 00-setup/01-pod-a.yaml
kubectl apply -f 00-setup/02-pod-b.yaml
kubectl apply -f 00-setup/03-names.yaml

kubectl -n ping-lab get pods -o wide --show-labels     # chờ cả 2 Pod Running
```

Xem container bên trong Pod:
```bash
kubectl -n ping-lab get pod pod-a -o jsonpath='{.spec.containers[*].name}'; echo   # shell
```

---

## BƯỚC 1. Chưa có policy nào: mọi thứ mở

```bash
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |

**Giải thích:** không có tờ giấy nào trên cửa, nên mọi cửa đều mở.

---

## BƯỚC 2. Khóa chiều VÀO của mọi Pod

```bash
kubectl apply -f 01-ingress/10-default-deny-ingress.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ⛔ | ⛔ | ⛔ | ✔ | ✔ | ✔ |

**Giải thích:**
- Cửa VÀO của cả A lẫn B đều có giấy trống, nên A và B không ping được nhau (1, 2, 3).
- DNS vẫn chạy (4): A đi RA tới CoreDNS, chiều ra chưa bị khóa. Gói trả lời của DNS
  quay về được nhờ conntrack (gói trả lời luôn được đi).
- Internet vẫn chạy (5, 6): cùng lý do, đó là chiều RA, và gói trả lời được đi.

---

## BƯỚC 3. Mở một chiều: cho A vào B

```bash
kubectl apply -f 01-ingress/11-allow-ingress-a-to-b.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ⛔ | ✔ | ✔ | ✔ | ✔ |

**Giải thích:**
- Cửa B giờ có 2 tờ: default-deny (không ai) + allow (Pod A). Gộp lại: chỉ A được vào B.
- B vẫn không ping được A (2): cửa A vẫn chỉ có giấy trống. **Policy chỉ mở MỘT chiều.**
- Khi A ping B, gói **trả lời** từ B về A vẫn đi được. Đó là trả lời, không phải B "gọi vào" A.

---

## BƯỚC 4. Khóa chiều RA của mọi Pod (chừa DNS)

```bash
kubectl apply -f 02-egress/20-default-deny-egress.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ⛔ | ⛔ | ⛔ | ✔ | ⛔ | ⛔ |

**Giải thích:**
- A→B (1) lại hỏng, dù cửa VÀO của B vẫn cho A. Lý do: giờ cửa RA của A chỉ cho đi tới
  CoreDNS. **Một kết nối phải qua 2 cửa: cửa RA của bên gửi và cửa VÀO của bên nhận.**
- A→B bằng tên (3) cũng hỏng: A **hỏi được** IP của pod-b (4 vẫn ✔), nhưng không được
  **đi tới** đó.
- Internet (5, 6) hỏng: chiều RA chỉ còn mở cho DNS. **Mở DNS không có nghĩa là mở Internet.**

---

## BƯỚC 5. Mở cửa RA của A tới B

```bash
kubectl apply -f 02-egress/21-allow-egress-a-to-b.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |

**Giải thích:** A→B đã đủ **2 tờ giấy**: cửa RA của A (bước 5) và cửa VÀO của B (bước 3).
Cửa RA của A giờ có 2 tờ, gộp lại: được đi tới CoreDNS + Pod B.

---

## BƯỚC 6a. Thử cho B vào A — chỉ dán MỘT tờ

```bash
kubectl apply -f 01-ingress/12-allow-ingress-b-to-a.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |

**Giải thích:** cửa VÀO của A đã cho B, nhưng **cửa RA của B vẫn chỉ cho đi tới DNS**
(bước 4). Thiếu một trong hai tờ là không thông. Đây là lỗi hay gặp nhất khi dùng egress.

---

## BƯỚC 6b. Dán tờ thứ hai: mở cửa RA của B tới A

```bash
kubectl apply -f 02-egress/22-allow-egress-b-to-a.yaml
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ✔ | ✔ | ✔ | ⛔ | ⛔ |

**Giải thích:** giờ B→A đủ 2 tờ (cửa RA của B + cửa VÀO của A). A và B ping được nhau
cả hai chiều, dùng được DNS, nhưng không ra được Internet. Đây chính là
**mẫu chuẩn: chặn hết (chừa DNS), rồi mở từng đường cụ thể.**

---

## BƯỚC 7 (thí nghiệm). Bài học "mất DNS"

Điều gì xảy ra nếu default deny egress **không chừa DNS**? File thí nghiệm có **cùng tên**
`default-deny-egress`, nên `apply` sẽ **cập nhật** policy đang có (báo `configured`),
không tạo thêm policy mới.

```bash
kubectl apply -f 99-thi-nghiem/default-deny-egress-no-dns.yaml    # configured
./test.sh
```

| 1 A→B IP | 2 B→A IP | 3 A→B tên | 4 DNS | 5 A→Internet | 6 B→Internet |
|:-:|:-:|:-:|:-:|:-:|:-:|
| ✔ | ✔ | ⛔ | ⛔ | ⛔ | ⛔ |

**Giải thích:**
- Ping **bằng IP** vẫn được (1, 2): các giấy phép A↔B vẫn còn.
- Ping **bằng TÊN** hỏng (3): muốn dùng tên thì phải hỏi DNS trước, mà DNS (4) bị chặn.
- **IP được, tên không được = dấu hiệu mất DNS.** Đây là lý do default deny egress
  luôn phải chừa DNS.

Trả về như cũ:
```bash
kubectl apply -f 02-egress/20-default-deny-egress.yaml            # configured
./test.sh                                                          # giống bước 6b
```

---

## Bảng tổng kết

| Bước | Thêm policy | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| 1 | (không có) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| 2 | default-deny-ingress | ⛔ | ⛔ | ⛔ | ✔ | ✔ | ✔ |
| 3 | allow-ingress-a-to-b | ✔ | ⛔ | ✔ | ✔ | ✔ | ✔ |
| 4 | default-deny-egress (chừa DNS) | ⛔ | ⛔ | ⛔ | ✔ | ⛔ | ⛔ |
| 5 | allow-egress-a-to-b | ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |
| 6a | allow-ingress-b-to-a | ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |
| 6b | allow-egress-b-to-a | ✔ | ✔ | ✔ | ✔ | ⛔ | ⛔ |
| 7 | (thí nghiệm) bỏ DNS khỏi default-deny-egress | ✔ | ✔ | ⛔ | ⛔ | ⛔ | ⛔ |

## Tự kiểm tra (làm sau bước 6b)

- Nếu bạn **xóa** `11-allow-ingress-a-to-b`, phép thử nào đổi kết quả?
- Nếu bạn **xóa** `21-allow-egress-a-to-b`, phép thử nào đổi kết quả?
- Muốn A ra được Internet (phép thử 5) thì phải dán thêm giấy gì, ở cửa nào?
  Gợi ý: dùng `ipBlock` với `cidr: 0.0.0.0/0`.

Thử bằng `kubectl delete -f <file>` rồi `./test.sh`, sau đó `kubectl apply -f <file>` để trả lại.

## Làm lại hoặc dọn dẹp

```bash
./reset-policies.sh     # gỡ mọi policy, giữ 2 Pod → quay lại BƯỚC 1
./cleanup.sh            # xóa toàn bộ namespace ping-lab
```
