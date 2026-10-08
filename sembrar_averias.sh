#!/bin/bash
# VC-TICKET-OK
# Siembra tres averías en el servidor DHCP del alumno según su número de lista.
# Uso: sudo bash sembrar_averias.sh N      (N = número de lista del alumno)
#
# SOLO PARA EL DOCENTE: este fichero contiene las soluciones. No lo distribuyas en claro;
# usa construir_ticket.sh para generar la versión cifrada.
#
# Reparto (N mod 4):
#   0 -> B1 B3 B7      1 -> B2 B4 B6      2 -> B1 B4 B5      3 -> B2 B3 B7
#
# Averías (todas sobre ficheros de la práctica; ninguna se ha probado todavía en una VM real):
#   B1  falta el ';' final de la línea range                       (dhcpd.conf)
#   B2  INTERFACESv4 apunta a otra interfaz                        (/etc/default/isc-dhcp-server)
#   B3  subred declarada con el tercer octeto cambiado             (dhcpd.conf)
#   B4  tabulador en el YAML de Netplan y enp0s8 sin IP            (netplan + ip addr flush)
#   B5  option routers fuera de la subred (tercer octeto cambiado) (dhcpd.conf)
#   B6  range reducido a una sola dirección                        (dhcpd.conf)
#   B7  último dígito de la MAC de la primera reserva cambiado     (dhcpd.conf)
#
# Variables solo para pruebas: VC_ROOT (raíz alternativa de ficheros) y VC_OTHER_IF.

set -u

R="${VC_ROOT:-}"
DHCPD="$R/etc/dhcp/dhcpd.conf"
DEFS="$R/etc/default/isc-dhcp-server"
NETPLAN="$(ls "$R"/etc/netplan/*.yaml 2>/dev/null | head -n1)"
MARK="$R/var/tmp/.vc-ticket-aplicado"

die() { echo "Error: $*" >&2; exit 1; }

[ -n "$R" ] || [ "$EUID" -eq 0 ] || die "ejecuta el script con sudo."
N="${1:-}"
[[ "$N" =~ ^[0-9]+$ ]] || die "indica tu número de lista, por ejemplo: sudo bash $0 7"
[ ! -e "$MARK" ] || die "el ticket ya se aplicó en esta máquina."
[ -f "$DHCPD" ] || die "falta $DHCPD. Completa antes la parte A."
[ -f "$DEFS" ] || die "falta $DEFS. Completa antes la parte A."
[ -n "$NETPLAN" ] && [ -f "$NETPLAN" ] || die "falta el fichero de Netplan."

IFACE_ORIG=$(sed -n -E 's/^INTERFACESv4="?([^" ]+)"?.*/\1/p' "$DEFS" | head -n1)
OTHER="${VC_OTHER_IF:-$(ls /sys/class/net 2>/dev/null | grep -v -e '^lo$' -e "^${IFACE_ORIG}\$" | head -n1)}"
OTHER="${OTHER:-enp0s3}"

b1() { sed -i -E '/^[[:space:]]*range[[:space:]]/ s/;[[:space:]]*$//' "$DHCPD"; }
b2() { sed -i -E "s/^(INTERFACESv4=).*/\1\"$OTHER\"/" "$DEFS"; }
b3() { perl -pi -e 's/^(\s*subnet\s+\d+\.\d+\.)(\d+)(\.)/$1.(($2+1)%256).$3/e' "$DHCPD"; }
b4() {
  perl -pi -e 'if(!$d && s/^\s+(addresses:)/\t$1/){$d=1}' "$NETPLAN"
  if [ -z "$R" ] && [ -n "$IFACE_ORIG" ]; then ip addr flush dev "$IFACE_ORIG" >/dev/null 2>&1; fi
}
b5() { perl -pi -e 's/^(\s*option\s+routers\s+\d+\.\d+\.)(\d+)(\.\d+\s*;)/$1.(($2+1)%256).$3/e' "$DHCPD"; }
b6() { perl -pi -e 's/^(\s*range\s+)([0-9.]+)\s+[0-9.]+(\s*;?)/$1$2 $2$3/' "$DHCPD"; }
b7() {
  perl -pi -e 'if(!$d && s/(hardware\s+ethernet\s+(?:[0-9a-fA-F]{2}:){5}[0-9a-fA-F])([0-9a-fA-F])/$1.sprintf("%x",(hex($2)+1)%16)/e){$d=1}' "$DHCPD"
}

case $((N % 4)) in
  0) FALLAS="b1 b3 b7" ;;
  1) FALLAS="b2 b4 b6" ;;
  2) FALLAS="b1 b4 b5" ;;
  3) FALLAS="b2 b3 b7" ;;
esac

INCOMPLETO=0
for f in $FALLAS; do
  antes=$(cat "$DHCPD" "$DEFS" "$NETPLAN" | md5sum)
  $f
  despues=$(cat "$DHCPD" "$DEFS" "$NETPLAN" | md5sum)
  [ "$antes" != "$despues" ] || INCOMPLETO=1
done

if [ -z "$R" ]; then systemctl restart isc-dhcp-server >/dev/null 2>&1 || true; fi

if [ "$INCOMPLETO" -eq 1 ]; then
  echo "Aviso: el ticket no pudo aplicarse por completo. Avisa al profesor." >&2
  exit 2
fi

mkdir -p "$(dirname "$MARK")" && touch "$MARK"
echo "Ticket VC-DHCP-001 recibido: el cliente informa de que el servidor DHCP de la sala de catas no reparte direcciones. Diagnostica y corrige."
