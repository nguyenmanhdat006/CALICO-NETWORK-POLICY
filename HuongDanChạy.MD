# HƯỚNG DẪN CHẠY TAY — LAB NetworkPolicy với ping

File này hướng dẫn chạy lab **hoàn toàn bằng tay**, không dùng `test.sh`.
Mọi lệnh chạy trên **k8s-cp**.

---

## PHẦN 0. Đưa folder lên k8s-cp

Trên máy tính của bạn (thay `user` bằng tên đăng nhập của k8s-cp):
```bash
scp ping-lab.zip user@192.168.56.10:~/
```

Trên **k8s-cp**:
```bash
cd ~
sudo apt-get install -y unzip      # nếu chưa có
unzip ping-lab.zip
cd ping-lab
```

---

## PHẦN 1. Tạo môi trường

```bash
kubectl apply -f 00-setup/00-namespace.yaml       # namespace ping-lab
kubectl apply -f 00-setup/01-pod-a.yaml           # Pod A
kubectl apply -f 00-setup/02-pod-b.yaml           # Pod B
kubectl apply -f 00-setup/03-names.yaml           # tên DNS cho 2 Pod
```

Kiểm tra, chờ cả 2 Pod `Running`:
```bash
kubectl -n ping-lab get pods -o wide --show-labels
```

---

## PHẦN 2. Lấy IP của 2 Pod

```bash
IP_A=$(kubectl -n ping-lab get pod pod-a -o jsonpath='{.status.podIP}')
IP_B=$(kubectl -n ping-lab get pod pod-b -o jsonpath='{.status.podIP}')
echo "IP_A=$IP_A   IP_B=$IP_B"
```

> ⚠️ Biến `IP_A`, `IP_B` chỉ sống trong cửa sổ terminal hiện tại. Mở cửa sổ mới
> thì chạy lại 3 lệnh trên.

---

## PHẦN 3. Bộ 6 lệnh kiểm tra (dùng lại ở mọi bước)

| STT | Lệnh | Kiểm tra gì |
|---|---|---|
| ① | `kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B` | A ping B bằng IP |
| ② | `kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A` | B ping A bằng IP |
| ③ | `kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b` | A ping B bằng TÊN |
| ④ | `kubectl -n ping-lab exec pod-a -- nslookup pod-b` | A hỏi DNS |
| ⑤ | `kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1` | A ra Internet |
| ⑥ | `kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1` | B ra Internet |

### Cách đọc kết quả

| Lệnh | ✔ Thông khi thấy | ⛔ Bị chặn khi thấy |
|---|---|---|
| ping | `64 bytes from ...` và `0% packet loss` | `100% packet loss` (chờ vài giây) |
| ping bằng tên khi DNS hỏng | | `bad address 'pod-b'` |
| nslookup | Có dòng `Name:` và `Address:` | `connection timed out; no servers could be reached` |

Xem các policy (tờ giấy) đang có, chạy bất cứ lúc nào:
```bash
kubectl -n ping-lab get networkpolicy
```

---

## BƯỚC 1. Chưa có policy nào

Không dán gì cả. Chạy 6 lệnh kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ✔
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ✔
```

**Vì sao:** chưa có tờ giấy nào trên cửa, mọi cửa đều mở.

---

## BƯỚC 2. Khóa chiều VÀO của mọi Pod

```bash
kubectl apply -f 01-ingress/10-default-deny-ingress.yaml
kubectl -n ping-lab get networkpolicy
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ⛔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ⛔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ⛔ (hỏi tên được, ping bị chặn)
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ✔
```

**Vì sao:**
- Cửa VÀO của A và B đều có giấy trống → A, B không ping được nhau.
- DNS và Internet là chiều RA, chưa bị khóa. Gói trả lời luôn được đi về.

---

## BƯỚC 3. Cho A vào B (chỉ một chiều)

```bash
kubectl apply -f 01-ingress/11-allow-ingress-a-to-b.yaml
kubectl -n ping-lab describe networkpolicy allow-ingress-a-to-b
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ⛔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ✔
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ✔
```

**Vì sao:**
- Cửa B có 2 tờ: default-deny (không ai) + allow (A). Gộp lại → chỉ A vào được B.
- Cửa A vẫn chỉ có giấy trống → B không vào được A. **Policy chỉ mở một chiều.**

---

## BƯỚC 4. Khóa chiều RA của mọi Pod (chừa DNS)

```bash
kubectl apply -f 02-egress/20-default-deny-egress.yaml
kubectl -n ping-lab get networkpolicy
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ⛔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ⛔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ⛔
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ⛔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ⛔
```

**Vì sao:**
- ① hỏng dù cửa VÀO của B vẫn cho A: cửa RA của A giờ chỉ cho đi tới CoreDNS.
  **Một kết nối phải qua 2 cửa: cửa RA bên gửi + cửa VÀO bên nhận.**
- ④ vẫn ✔: DNS được chừa sẵn trong file 20.
- ⑤ ⑥ hỏng: **mở DNS không có nghĩa là mở Internet.**

---

## BƯỚC 5. Mở cửa RA của A tới B

```bash
kubectl apply -f 02-egress/21-allow-egress-a-to-b.yaml
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ⛔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ✔
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ⛔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ⛔
```

**Vì sao:** A→B đã đủ **2 tờ**: cửa RA của A (bước 5) + cửa VÀO của B (bước 3).

---

## BƯỚC 6a. Cho B vào A — mới dán MỘT tờ

```bash
kubectl apply -f 01-ingress/12-allow-ingress-b-to-a.yaml
```

Kiểm tra (chỉ cần lệnh ②):
```bash
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ⛔ vẫn bị chặn!
```

**Vì sao:** cửa VÀO của A đã cho B, nhưng **cửa RA của B** vẫn chỉ cho đi tới DNS.
Thiếu một tờ là không thông.

---

## BƯỚC 6b. Dán tờ thứ hai: mở cửa RA của B tới A

```bash
kubectl apply -f 02-egress/22-allow-egress-b-to-a.yaml
kubectl -n ping-lab get networkpolicy        # giờ có 6 policy
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ✔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 $IP_A      # ② ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ✔
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 1.1.1.1    # ⑤ ⛔
kubectl -n ping-lab exec pod-b -- ping -c 2 -W 2 1.1.1.1    # ⑥ ⛔
```

**Vì sao:** B→A đủ 2 tờ. A và B ping được nhau cả hai chiều, có DNS, không có Internet.
Đây là **mẫu chuẩn: chặn hết (chừa DNS), rồi mở từng đường cụ thể.**

---

## BƯỚC 7 (thí nghiệm). Bài học "mất DNS"

File thí nghiệm **cùng tên** `default-deny-egress` nhưng không chừa DNS.
`apply` sẽ **cập nhật** policy đang có (báo `configured`).

```bash
kubectl apply -f 99-thi-nghiem/default-deny-egress-no-dns.yaml
```

Kiểm tra:
```bash
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 $IP_B      # ① ✔ bằng IP vẫn được
kubectl -n ping-lab exec pod-a -- ping -c 2 -W 2 pod-b      # ③ ⛔ bad address 'pod-b'
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ⛔ no servers could be reached
```

**Vì sao:** muốn dùng tên thì phải hỏi DNS trước, mà DNS bị chặn.
**IP được, tên không được = dấu hiệu mất DNS.**

Trả về như cũ:
```bash
kubectl apply -f 02-egress/20-default-deny-egress.yaml
kubectl -n ping-lab exec pod-a -- nslookup pod-b            # ④ ✔ trở lại
```

---

## Bảng tổng kết

| Bước | Thêm policy | ① | ② | ③ | ④ | ⑤ | ⑥ |
|---|---|:-:|:-:|:-:|:-:|:-:|:-:|
| 1 | (không có) | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| 2 | default-deny-ingress | ⛔ | ⛔ | ⛔ | ✔ | ✔ | ✔ |
| 3 | allow-ingress-a-to-b | ✔ | ⛔ | ✔ | ✔ | ✔ | ✔ |
| 4 | default-deny-egress (chừa DNS) | ⛔ | ⛔ | ⛔ | ✔ | ⛔ | ⛔ |
| 5 | allow-egress-a-to-b | ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |
| 6a | allow-ingress-b-to-a | ✔ | ⛔ | ✔ | ✔ | ⛔ | ⛔ |
| 6b | allow-egress-b-to-a | ✔ | ✔ | ✔ | ✔ | ⛔ | ⛔ |
| 7 | thí nghiệm: bỏ DNS | ✔ | ✔ | ⛔ | ⛔ | ⛔ | ⛔ |

---

## Làm lại hoặc dọn dẹp

Gỡ mọi policy, giữ 2 Pod (quay về bước 1):
```bash
kubectl -n ping-lab delete networkpolicy --all
```

Xóa toàn bộ lab:
```bash
kubectl delete namespace ping-lab
```
