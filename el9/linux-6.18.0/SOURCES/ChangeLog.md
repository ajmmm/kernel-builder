**Kernel 6.18**

v0.rc2:
- Rebase to kernel 6.18-rc2
- aarch64 configuration updated via linux-src olddefconfig
- x86_64 configuration rebased via config merge and may not work

v0.rc2.1:
- CONFIG_IPV6_SEG6_LWTUNNEL=y
- CONFIG_IPV6_SEG6_HMAC=y
- CONFIG_IPV6_SEG6_BPF=y
