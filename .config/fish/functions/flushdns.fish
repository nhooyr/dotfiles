# Defined in /var/folders/7b/218sfv615xxf_w9ttnpjt0_r0000gn/T//fish.Qp1SvU/flushdns.fish @ line 2
function flushdns
	sudo killall -HUP mDNSResponder
  sudo killall mDNSResponderHelper
  sudo dscacheutil -flushcache
end
