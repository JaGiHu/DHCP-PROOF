#!/bin/bash
# Genera la versión cifrada del ticket que se reparte a los alumnos.
# Uso: bash construir_ticket.sh sembrar_averias.sh 'clave' > ticket_vc_dhcp_001.sh
# La clave se da de viva voz al empezar la sesión. Sin ella, el fichero no revela las averías.
set -eu
SRC="${1:?falta el script de averías}"
PASS="${2:?falta la clave}"

PAYLOAD=$(openssl enc -aes-256-cbc -pbkdf2 -salt -pass "pass:$PASS" -in "$SRC" | base64 -w0)

cat <<EOF
#!/bin/bash
# Ticket VC-DHCP-001 · Bodegas Valcorral
# Uso: sudo bash ticket_vc_dhcp_001.sh N      (N = tu número de lista)
read -rsp "Clave del ticket: " K; echo
PLAIN=\$(printf '%s' '$PAYLOAD' | base64 -d | openssl enc -d -aes-256-cbc -pbkdf2 -pass "pass:\$K" 2>/dev/null | tr -d "\\000") || { echo "Clave incorrecta."; exit 1; }
case "\$PLAIN" in "#!/bin/bash"*"VC-TICKET-OK"*) ;; *) echo "Clave incorrecta."; exit 1;; esac
printf '%s\n' "\$PLAIN" | bash -s -- "\$@"
EOF
