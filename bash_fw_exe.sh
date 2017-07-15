#!/bin/bash

PATH=$PATH:/sbin:/usr/sbin:/bin:/usr/bin

############################################################
## SCRIPT DI CONFIGURAZIONE IPTABLES PER FIREWALL A 3 INTERFACCE:
##
## EXTERNAL - Tipicamente con IP pubblici, con accesso IPSEC e PPTP
## DMZ - Per server pubblici, nattati, esposti alla rete pubblica
## INTERNAL - Permette l'accesso Internet ai client della rete interna
##
## INSTRUZIONI PER L'USO
## Lo script è diviso in varie parti:
## - Definizione di Variabili generali (modifica necessaria)
## - Impostazione parametri del kernel (modifica facoltativa)
## - Impostazione regole generali (modifica facoltativa)
## - Impostazione regole per specifiche funzioni (DMZ, VPN, LAN NAT ecc.)
##   (Attivare/Disattivare e impostare parametri secondo proprie necessità)
##
## Versione 0.2 - ISO 9001
## Revisione 20070328
############################################################

## Impostazione indirizzo IP primario delle interfacce:
## esterna (ext), dmz (dmz), interna (int)
extip="151.151.151.151"
dmzip="172.16.0.1"
intip="192.168.0.1"

## Associazione interfacce alle reti:
## esterna (ext), dmz (dmz), interna (int)
extint="eth0"
dmzint="eth2"
intint="eth1"

## Indirizzi delle reti:
## esterna (ext), dmz (dmz), interna (int)
extnet="151.151.151.0/24"
dmznet="172.16.0.0/16"
intnet="192.168.0.0/24"


############################################################
## IMPOSTAZIONE PARAMETRI E CARICAMENTO MODULI DEL KERNEL
## Possono essere impostati anche su /etc/sysctl.conf
############################################################

## Abilita IP forwarding (fondamentale)
echo "1" > /proc/sys/net/ipv4/ip_forward

## Non risponde a ping su broadcast
echo "1" > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts

## Abitilita protezione da messaggi di errore
echo "1" > /proc/sys/net/ipv4/icmp_ignore_bogus_error_responses

## Non accetta icmp redirect
echo "0" > /proc/sys/net/ipv4/conf/all/accept_redirects

## Abilita protezione (parziale) antispoof
echo "1" > /proc/sys/net/ipv4/conf/all/rp_filter

## Logga pacchetti strani o impossibili
echo "1" > /proc/sys/net/ipv4/conf/all/log_martians

## Pre-carica i moduli del kernel che servono
modprobe ip_tables
modprobe iptable_nat
modprobe ip_nat_ftp
modprobe ip_conntrack_ftp
modprobe ipt_MASQUERADE




############################################################
## IMPOSTAZIONE REGOLE IPTABLES GENERALI
## Questa parte, in linea di massima, non necessita customizzazioni
## In questo script si segue questa logica:
## - Drop di default di ogni pacchetto
## - AGGIUNTA di regole sul traffico accettato
## - Log finale dei pacchetti prima che siano droppati
##
## Per ottimizzare le prestazioni può servire modificare l'ordine
## delle regole, inserendo per prime quelle più utilizzate.
## Si suggerisce, nel caso, di riordinare interi blocchi di configurazione
## (regole per dmz, nat, ipsec ecc.) facendo sempre attenzione all'ordine
## con cui sono aggiunte le regole per evitare disfunzioni
## Nota: Lo script è stato testato solo con l'ordine qui impostato.
############################################################

## Azzeramento di ogni regola e counter esistenti
iptables -t filter -F
iptables -t filter -X
iptables -t filter -Z
iptables -t mangle -F
iptables -t mangle -X
iptables -t mangle -Z
iptables -t nat -F
iptables -t nat -X
iptables -t nat -Z

## Impostazione policy di default
iptables -P INPUT DROP
iptables -P OUTPUT DROP
iptables -P FORWARD DROP
iptables -t nat -P POSTROUTING ACCEPT
iptables -t nat -P PREROUTING ACCEPT
iptables -t nat -P OUTPUT ACCEPT
iptables -t mangle -P OUTPUT ACCEPT
iptables -t mangle -P INPUT ACCEPT
iptables -t mangle -P FORWARD ACCEPT
iptables -t mangle -P POSTROUTING ACCEPT
iptables -t mangle -P PREROUTING ACCEPT

## Abilitazione traffico di loopback
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT




############################################################
## TRAFFICO IN ENTRATA E IN USCITA DAL FIREWALL
## Adattare secondo proprie preferenze
############################################################

## INDIRIZZO IP o RETE da cui è possibile accedere al firewall (ssh)
## Inserire un indirizzo di amministrazione
admin="100.0.0.254"


############################################################
## INPUT - Traffico permesso in ingresso verso il firewall

## Accesso dalla rete interna (su porta ssh e proxy)
iptables -A INPUT -s $intnet -i $intint -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -s $intnet -i $intint -p tcp --dport 3128 -j ACCEPT

## Accesso incondizionato da indirizzo di amministrazione 
iptables -A INPUT -s $admin -j ACCEPT

## Viene permesso in entrata il traffico correlato a connessioni già esistenti
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

## Abilitazione pacchetti ICMP (es: ping) da rete interna e dmz
iptables -A INPUT -p icmp -i $dmzint -j ACCEPT
iptables -A INPUT -p icmp -i $intint -j ACCEPT


############################################################
## OUTPUT - Traffico permesso in uscita dall'host del firewall
## Vengono proposte 2 alternative (commentare una o l'altra):
## A) Traffico in uscita ristretto (potrebbe impedire alcune attività di sistema)
## B) Traffico in uscita dal firewall libero (viene solo fatto un sanity check)

## A) Il firewall può pingare e uscire via ssh, stmp, dns:
# iptables -A OUTPUT -p icmp -j ACCEPT
# iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 25 -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 22227 -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 21 -j ACCEPT
# iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

## Dal firewall si può navigare sul web (necessario per proxy)
# iptables -A OUTPUT -p tcp --dport 80 -j ACCEPT
# iptables -A OUTPUT -p tcp --dport 443 -j ACCEPT


## B) I pacchetti in uscita dal firewall all'esterno non hanno filtri
iptables -A OUTPUT -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT




############################################################
## REGOLE PER VPN IPSEC LAN 2 LAN
## Necessarie per permettere il collegamento ad un peer ipsec remoto
## e gestire il traffico fra le due reti
## Modificare i parametri secondo proprie necessità
############################################################

## Definizione degli indirizzi IP (pubblici) dei due peer IPSEC
## Server locale, questo (local) - Peer IpSec remoto (remote)
remote="212.212.212.212"
local="151.151.151.151"

## Rete locale e remota da mettere in comunicazione via ipsec
## (Coincidono con "leftsubnet" e "rightsubnet" di OpenSwan)
locallan="192.168.1.0/24"
remotelan="192.168.0.0/24"


############################################################
## Regole per ogni peer di una VPN IPSEC LAN 2 LAN

iptables -A OUTPUT -d $remote -p udp --dport 500 -j ACCEPT
iptables -A OUTPUT -d $remote -p ah -j ACCEPT
iptables -A OUTPUT -d $remote -p esp -j ACCEPT

iptables -A INPUT -s $remote -p udp --sport 500 -j ACCEPT
iptables -A INPUT -s $remote -p ah -j ACCEPT
iptables -A INPUT -s $remote -p esp -j ACCEPT

## Regole per IPSEC LAN 2 LAN con NAT-TRAVERSAL
## AGGIUNGERE le seguenti regole se è previsto l'uso di NAT-T
iptables -A OUTPUT -d $remote -p udp --dport 4500 -j ACCEPT
iptables -A INPUT -s $remote -p udp --dport 4500 -j ACCEPT

## Regola per permettere al server locale di contattare macchine della rete remota
iptables -A OUTPUT -d $remotelan -j ACCEPT


############################################################
## Regole per permettere ad un CLIENT VPN IPSEC INTERNO
## di collegarsi ad un server IPsec esterno
## Scommentare e usare se necessario

$ipsecserver = "21.21.21.21"
# iptables -A FORWARD -s $intnet -i $intint -p udp -d $ipsecserver -j ACCEPT
# iptables -A FORWARD -s $intnet -i $intint -p ah -d $ipsecserver -j ACCEPT
# iptables -A FORWARD -s $intnet -i $intint -p esp -d $ipsecserver -j ACCEPT


############################################################
## Definizione del traffico permesso fra le due reti
## Qui non vengono impostate alcune limitazioni:
## le due reti non hanno filtri tra loro.
## Restringere queste impostazioni secondo proprie necessità, nell'impostare
## gli indirizzi degli HOST delle LAN, usare il loro IP interno

iptables -A FORWARD -s $locallan -d $remotelan -j ACCEPT
iptables -A FORWARD -s $remotelan -d $locallan -j ACCEPT




############################################################
## REGOLE PER VPN PPTP
## Impostazioni per:
## - Permettere accesso PPTP da Internet a server locale
## - Permettere accesso PPTP da host locale a un pptp server esterno
## - Permettere accesso PPTP da host locale a qualsiasi pptp server
## - Permettere a client della rete interna di accedere ad un pptp server esterno
## - Permettere a client della rete interna di accedere a qualsiasi pptp server
## NOTA: Scommentare le regole che interessano
############################################################

## Indirizzo IP di un server PPTP esterno
pptpserver="85.85.85.85"


############################################################
## Regole per permettere accesso PPTP da Internet a server locale
iptables -A INPUT -p tcp --dport 1723 -j ACCEPT
iptables -A INPUT -p gre -j ACCEPT
iptables -A OUTPUT -p gre -j ACCEPT

## Ciclo per regole da applicare alle interfacce pptp create con il tunnel
## Da adattare se si prevede di avere più di 10 tunnel contemporaneamente.
for i in 0 1 2 3 4 5 6 7 8 9 ; do
    iptables -A FORWARD -i ppp$i -j ACCEPT
    iptables -A FORWARD -i $intint -o ppp$i -j ACCEPT
    iptables -A OUTPUT -o ppp$i -j ACCEPT
    iptables -A INPUT -i ppp$i -p icmp -j ACCEPT
done


############################################################
## Regole per permettere accesso PPTP da host locale a un pptpserver esterno
iptables -A OUTPUT -p tcp --dport 1723 -d $pptpserver -j ACCEPT
iptables -A OUTPUT -p gre -d $pptpserver -j ACCEPT


############################################################
## Regole per permettere accesso PPTP da host locale a qualsiasi server
# iptables -A OUTPUT -p tcp --dport 1723 -j ACCEPT
# iptables -A OUTPUT -p gre -j ACCEPT


############################################################
## Regole per permettere a client della LAN di accedere ad un pptpserver esterno
# iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 1723 -d $pptpserver -j ACCEPT
# iptables -A FORWARD -s $intnet -i $intint -p gre -d $pptpserver -j ACCEPT


############################################################
## Regole per permettere a client della LAN di accedere a qualsiasi server pptp
# iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 1723 -j ACCEPT
# iptables -A FORWARD -s $intnet -i $intint -p gre -j ACCEPT




############################################################
## LOCAL LAN NATTING (MASQUERADING)
## Impostazioni che permettono il natting (masquerading) della rete interna (LAN)
## e determinano quale traffico è concesso dalla rete interna verso Internet
## Adattare secondo proprie necessità
############################################################

## Indirizzo IP assegnato ai client quando escono su Internet
## Deve stare sull'interfaccia esterna e può essere lo stesso $extip
## precedentemente definito
## Se si usa un indirizzo diverso ricordarsi di abilitarlo come alias
## sull'interfaccia esterna (si può fare direttamente in questo script:
ifconfig eth0:1 151.151.151.152 netmask 255.255.255.0 broadcast 151.151.151.255

#extiplan=$extip
extiplan="151.151.151.152"

## Vengono proposte due alternative:
## A) Natting della rete locale con esclusione degli indirizzi della LAN remota
## B) Normale natting di tutta la rete locale
## Utilizzare A se il firewall è anche peer di una VPN ipsec lan-to-lan
## Nota: Se si usa l'opzione A, assicurarsi che questo blocco di regole sia
## successivo a quello relativo alla VPN IPsec

## A) LAN natting in caso di utilizzo VPN IPsec lan 2 lan:
# iptables -t nat -A POSTROUTING -s $intnet -d ! $remotelan -j SNAT --to-source $extiplan

## B) LAN natting normale
iptables -t nat -A POSTROUTING -o $extint -s $intnet -j SNAT --to-source $extiplan


############################################################
## Definizione del traffico Internet permesso ai client della rete Interna
## Vengono proposte due alternative:
## A) Libero accesso ad Internet a tutti i client della rete Interna
## B) Accesso limitato ai client della rete interna

## A) Libero accesso ad Internet a tutti i client della rete Interna
# iptables -A FORWARD -s $intnet -i $intint -j ACCEPT

## B) Accesso limitato ai client della rete interna
## Qui solo traffico di posta, dns e ssh (di default lo script prevede l'uso
## di un proxy locale per la navigazione dei client)
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 21 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 22 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 25 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 110 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 143 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 995 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 993 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 80  -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 443 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p tcp --dport 3389 -j ACCEPT
iptables -A FORWARD -s $intnet -i $intint -p udp --dport 3389 -j ACCEPT



############################################################
## Viene accettato il traffico di ritorno a connessioni già stabilite
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT




############################################################
## DMZ
## Impostazioni che nattano i server presenti in DMZ e li rendono accessibili
## ad Internet sulle porte dei servizi di produzione
## Adattare e ampliare secondo proprie necessità
############################################################


############################################################
## Regole generali per permettere ai server in DMZ di accedere a servizi pubblici
## Sono proposti 2 approcci alternativi:
## A) Nessun filtro in uscita dalla DMZ
## B) Traffico in uscita limitato (può filtrare traffico necessario,customizzare)

## A) Nessun filtro in uscita dalla DMZ
# iptables -A FORWARD -i $dmzint -o ! $intint -j ACCEPT

## B) Traffico in uscita limitato (customizzare)
##
## iptables -A FORWARD -s $dmznet -i $dmzint  -j DROP

iptables -A FORWARD -i $dmzint -o ! $intint -p tcp --dport 25 -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p tcp --dport 80 -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p udp --dport 53 -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p tcp --dport 25 -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p icmp --icmp-type destination-unreachable -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p icmp --icmp-type echo-reply -j ACCEPT
iptables -A FORWARD -i $dmzint -o ! $intint -p icmp --icmp-type echo-request -j ACCEPT



############################################################
## Accesso totale da indirizzo di amministrazione anche a server in DMZ
# iptables -A FORWARD -s $admin -j ACCEPT


##########################################################################
## Regole sul traffico da LAN a DMZ (accesso completo, restringere secondo necessità)
iptables -A FORWARD -s $intnet -i $intint -d $dmznet -o $dmzint -j ACCEPT


############################################################
## Natting di un server web, con accesso http pubblico e ftp da IP
## del webmaster.
## Vengono proposte due alternative:
## A) Natting 1 a 1, dove un IP pubblico corrisponde ad un IP interno
## B) Natting 1 a molti, dove a seconda della porta si redireziona su un diverso host interno

## IP pubblico del webserver (su rete esterna):
#extipwebserver="172.16.0.30"

## Impostazione IP aliasing su interfaccia pubblica
#ifconfig eth0:2 10.0.1.4 netmask 255.255.255.0 broadcast 10.0.0.255

## IP privato del webserver (su dmz)
#webserver="172.16.0.30"

## IP da cui può accedere un webmaster via ftp
#webmaster="10.0.0.150"

## A) NATTING 1-1 (Viene usato l'IP esterno definito in: $extipwebserver)
#iptables -t nat -A PREROUTING -d $extipwebserver -j DNAT --to-destination $webserver
#iptables -t nat -A POSTROUTING -s $webserver -j SNAT --to-source $extipwebserver

## B) NATTING 1-* (Viene usato l'IP esterno del firewall)
#iptables -t nat -A PREROUTING -d $extip -p tcp --dport 80 -j DNAT --to-destination $webserver:80

## Regole di firewalling per permettere l'accesso da Internet ai servizi in DMZ
#iptables -A FORWARD -d $webserver -p tcp --dport 80 -j ACCEPT
#iptables -A FORWARD -d $webserver -s $webmaster -p tcp --dport 21 -j ACCEPT


############################################################
## Natting di un terminal server.
## Sono definite le stesse logiche del webserver di cui sopra
## In forma compatta. Come sempre le opzioni A) o B) sono ALTERNATIVE fra loro

## IP Pubblico terminal server (solo per opzione A)
# extipterminalserver="10.0.0.3"
# ifconfig eth0:3 10.0.0.3 netmask 255.255.255.0 broadcast 10.0.0.255


## IP privato (in DMZ) del terminal server
ifconfig $dmzint  172.16.0.178 netmask 255.255.0.0
terminalserver="172.16.0.3"

## A) Natting 1-1
# iptables -t nat -A PREROUTING -d $extipterminalserver -j DNAT --to-destination $terminalserver
# iptables -t nat -A POSTROUTING -s $terminalserver -j SNAT --to-source $extipterminalserver

## A) Natting 1-*
iptables -t nat -A PREROUTING -d $extip -p tcp --dport 3389 -j DNAT --to-destination $terminalserver:3389

## Traffico concesso da Internet a porta 3389 Terminal Server
iptables -A FORWARD -d $terminalserver -p tcp --dport 3389 -j ACCEPT


############################################################
## Source natting degli IP della DMZ su IP esterno
## Lasciare alla fine del blocco relativo alla DMZ
iptables -t nat -A POSTROUTING -s $dmznet -j SNAT --to-source $extip



############################################################
## LOGGING dei pacchetti droppati
## Regole da inserire alla fine, appena prima del DROP di default
## Notare che non vengono loggati eventuali pacchetti droppati precedentemente
## Vegnono loggati solo pacchetti unicast (no broadcast/multicast) con prefisso
############################################################

iptables -A INPUT -m pkttype --pkt-type unicast -j LOG --log-prefix "INPUT DROP: "
iptables -A OUTPUT -m pkttype --pkt-type unicast -j LOG --log-prefix "OUTPUT DROP: "
iptables -A FORWARD -m pkttype --pkt-type unicast -j LOG --log-prefix "FORWARD DROP: "

exit 0