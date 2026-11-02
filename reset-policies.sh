#!/usr/bin/env bash
# Gỡ MỌI NetworkPolicy trong ping-lab, giữ nguyên Pod.
# Dùng khi muốn làm lại các bước từ đầu.
kubectl -n ping-lab delete networkpolicy --all
