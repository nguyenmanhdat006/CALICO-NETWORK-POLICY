#!/usr/bin/env bash
# Chạy 6 phép thử ping/DNS và in bảng kết quả.
# Cách dùng:  ./test.sh
NS=ping-lab

IP_A=$(kubectl -n $NS get pod pod-a -o jsonpath='{.status.podIP}')
IP_B=$(kubectl -n $NS get pod pod-b -o jsonpath='{.status.podIP}')

# Hàm chạy một lệnh trong Pod, trả về ✔ nếu thành công, ⛔ nếu thất bại
run() {   # run <pod> <lệnh...>
  local pod=$1; shift
  if timeout 15 kubectl -n $NS exec "$pod" -- "$@" >/dev/null 2>&1; then echo "✔"; else echo "⛔"; fi
}
dns() {   # dns <pod> <tên>: thành công nếu nslookup trả về dòng "Name:"
  if timeout 15 kubectl -n $NS exec "$1" -- nslookup "$2" 2>&1 | grep -q '^Name:'; then echo "✔"; else echo "⛔"; fi
}

echo "IP pod-a = $IP_A    IP pod-b = $IP_B"
echo
echo "Policy đang có trong namespace $NS:"
kubectl -n $NS get networkpolicy 2>&1 | sed 's/^/   /'
echo
echo "Đang thử, mỗi phép thử bị chặn sẽ mất vài giây..."
echo
printf "%-4s %-34s %s\n" "STT" "Phép thử" "Kết quả"
printf "%-4s %-34s %s\n" "1" "A ping B   (bằng IP)"        "$(run pod-a ping -c 1 -W 2 "$IP_B")"
printf "%-4s %-34s %s\n" "2" "B ping A   (bằng IP)"        "$(run pod-b ping -c 1 -W 2 "$IP_A")"
printf "%-4s %-34s %s\n" "3" "A ping B   (bằng TÊN pod-b)" "$(run pod-a ping -c 1 -W 2 pod-b)"
printf "%-4s %-34s %s\n" "4" "A hỏi DNS  (nslookup pod-b)"  "$(dns pod-a pod-b)"
printf "%-4s %-34s %s\n" "5" "A ping Internet (1.1.1.1)"   "$(run pod-a ping -c 1 -W 2 1.1.1.1)"
printf "%-4s %-34s %s\n" "6" "B ping Internet (1.1.1.1)"   "$(run pod-b ping -c 1 -W 2 1.1.1.1)"
echo
echo "✔ = thông    ⛔ = bị chặn"
