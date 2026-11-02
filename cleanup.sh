#!/usr/bin/env bash
# Xóa toàn bộ bài lab (namespace, 2 Pod, Service, mọi NetworkPolicy bên trong)
kubectl delete namespace ping-lab --ignore-not-found
