#!/usr/bin/env bash

####
#
#  Install Script. run to configure various components
#
#  exit codes:
#  9 - install error
#  5 - user cancel
#
####

###########################################################
## CONFIG SECTION
###########################################################


readonly version=0.4

# target directory for server components
TARGETDIR="/srv"
DSHIELDDIR="${TARGETDIR}/dshield"
# COWRIEDIR="${TARGETDIR}/cowrie"
LOGDIR="${TARGETDIR}/log"
LOGFILE="${LOGDIR}/install_`date +'%Y-%m-%d_%H%M%S'`.log"

# which ports will be handled e.g. by cowrie (separated by blanks)
# used e.g. for setting up block rules for trusted nets
# use the ports after PREROUTING has been excecuted, i.e. the redirected (not native) ports
HONEYPORTS="2222"

# Debug Flag
DEBUG=1

# delimiter
LINE="##########################################################################################################"

# dialog stuff
: ${DIALOG_OK=0}
: ${DIALOG_CANCEL=1}
: ${DIALOG_HELP=2}
: ${DIALOG_EXTRA=3}
: ${DIALOG_ITEM_HELP=4}
: ${DIALOG_ESC=255}

export NCURSES_NO_UTF8_ACS=1


###########################################################
## FUNCTION SECTION
###########################################################

# echo and log
outlog () {
   echo ${*}
   do_log ${*}
}

# write log
do_log () {
   if [ ! -d ${LOGDIR} ] ; then
       mkdir -p ${LOGDIR}
       chmod 700 ${LOGDIR}
   fi
   if [ ! -f ${LOGFILE} ] ; then
       touch ${LOGFILE}
       chmod 600 ${LOGFILE}
       outlog "Log ${LOGFILE} started."
       do_log "ATTENTION: the log file contains sensitive information (e.g. passwords, API keys, ...)"
       do_log "           Handle with care. Sanitize before submitting."
   fi
   echo "`date +'%Y-%m-%d_%H%M%S'` ### ${*}" >> ${LOGFILE}
}

# execute and log
run () {
   do_log "Running: ${*}"
   eval ${*} >> ${LOGFILE} 2>&1
   return ${?}
}

# run if debug is set
drun () {
   if [ ${DEBUG} -eq 1 ] ; then
      do_log "DEBUG COMMAND FOLLOWS:"
      do_log "${LINE}"
      run ${*}
      RET=${?}
      do_log "${LINE}"
      return ${RET}
   fi
}

# log if debug is set
dlog () {
   if [ ${DEBUG} -eq 1 ] ; then
      do_log "DEBUG OUTPUT: ${*}"
   fi
}

###########################################################
## MAIN
###########################################################

echo ${LINE}

userid=`id -u`
if [ ! "$userid" = "0" ]; then
   echo "You have to run this script as root. eg."
   echo "  sudo bin/install.sh"
   echo "Exiting."
   exit 9
else
   do_log "Check OK: User-ID is ${userid}."
fi

dlog "This is ${0} V${version}"

if [ ${DEBUG} -eq 1 ] ; then
   do_log "DEBUG flag is set."
else
   do_log "DEBUG flag NOT set."
fi

drun env


outlog "Checking Pre-Requisits"

progname=$0;
progdir=`dirname $0`;
progdir=$PWD/$progdir;

dlog "progname: ${progname}"
dlog "progdir: ${progdir}"

cd $progdir

if [ ! -f /etc/os-release ] ; then
  outlog "I can not fine the /etc/os-release file. You are likely not running a supported operating systems"
  outlog "please email info@dshield.org for help."
  exit 9
fi

drun "cat /etc/os-release"
drun "uname -a"

. /etc/os-release


dist=invalid


if [ "$ID" == "ubuntu" ] ; then
   dist='apt';
fi

if [ "$ID" == "raspbian" ] && [ "$VERSION_ID" == "8" ] ; then
   dist='apt';
fi

if [ "$ID" == "amzn" ] && [ "$VERSION_ID" == "2016.09" ] ; then 
   dist='yum';
fi

dlog "dist: ${dist}"

if [ "$dist" == "invalid" ] ; then
   outlog "You are not running a supported operating systems. Right now, this script only works for Raspbian and Amazon Linux AMI."
   outlog "Please ask info@dshield.org for help to add support for your OS. Include the /etc/os-release file."
   exit 9
fi

outlog "using apt to install packages"

dlog "creating a temporary directory"

TMPDIR=`mktemp -d -q /tmp/dshieldinstXXXXXXX`
dlog "TMPDIR: ${TMPDIR}"
dlog "setting trap"
# trap "rm -r $TMPDIR" 0 1 2 5 15
run 'trap "rm -r $TMPDIR" 0 1 2 5 15'

outlog "Basic security checks"

dlog "making sure default password was changed"

if [ "$dist" == "apt" ]; then
   if $progdir/passwordtest.pl | grep -q 1; then
      outlog "You have not yet changed the default password for the 'pi' user"
      outlog "Change it NOW ..."
      exit 9
   fi
   outlog "Updating your Installation (this can take a LOOONG time)"

   drun dpkg --list

   run 'apt-get update'
   run 'apt-get -y -q upgrade'

   outlog "Installing additional packages"
   # apt-get -y -qq install build-essential dialog git libffi-dev libmpc-dev libmpfr-dev libpython-dev libswitch-perl libwww-perl mini-httpd mysql-client python2.7-minimal python-crypto python-gmpy python-gmpy2 python-mysqldb python-pip python-pyasn1 python-twisted python-virtualenv python-zope.interface randomsound rng-tools unzip libssl-dev > /dev/null

   # OS packages: no python modules
   run 'apt-get -y -q install build-essential dialog git libffi-dev libmpc-dev libmpfr-dev libpython-dev libswitch-perl libwww-perl mini-httpd mysql-client python2.7-minimal randomsound rng-tools unzip libssl-dev'
   # pip install python-dateutil > /dev/null

fi

if [ "$ID" == "amzn" ]; then
   outlog "Updating your Operating System"
   run 'yum -q update -y'
   outlog "Installing additional packages"
   # run yum -q install -y dialog perl-libwww-perl perl-Switch python27-twisted python27-crypto python27-pyasn1 python27-zope-interface python27-pip mysql rng-tools boost-random MySQL-python27 python27-dateutil 
   run 'yum -q install -y dialog perl-libwww-perl perl-Switch mysql rng-tools boost-random MySQL-python27'
fi


# last chance to escape before hurting the system ...

dialog --title 'WARNING' --yesno "You are about to turn this Raspberry Pi into a honeypot. This software assumes that the device is DEDICATED to this task. There is no simple uninstall. Do you want to proceed?" 10 50
response=$?
case $response in
   ${DIALOG_CANCEL}) 
      outlog "Terminating installation by your command. The system shouldn't have been hurt too much yet ..."
      outlog "See ${LOGFILE} for details."
      exit 5
      ;;
esac


outlog "check if pip is already installed"

run 'pip > /dev/null'

if [ ${?} -gt 0 ] ; then
   # nice, no pip found

   dlog "no pip found, Installing pip"

   run 'wget -qO $TMPDIR/get-pip.py https://bootstrap.pypa.io/get-pip.py'
   run 'python $TMPDIR/get-pip.py'

else
   # hmmmm ...
   # todo: automatic check if pip is OS managed or not
   # let's assume local is pip, non local is distro

   outlog "pip found .... Checking which pip is installed...."

   drun 'pip -V'
   drun 'pip  -V | cut -d " " -f 4 | cut -d "/" -f 3'
   drun 'find /usr -name pip'
   drun 'find /usr -name pip | grep -v local'

   if [ `pip  -V | cut -d " " -f 4 | cut -d "/" -f 3` != "local" -o `find /usr -name pip | grep -v local | wc -l` -gt 0 ] ; then
      # pip may be distro pip

      outlog "Potential distro pip found"

      dialog --title 'NOTE (pip)' --yesno "pip is already installed on the system... and it looks like as being installed as a distro package. If this is true, it can be problematic in the future and cause esoteric errors. You may consider uninstalling all OS packages of Python modules. Proceed nevertheless?" 12 50
      response=$?
      case $response in
         ${DIALOG_CANCEL}) 
            do_log "Terminated by user in pip dialogue."
            exit 5
            ;;
      esac

   else
      outlog "pip found which doesn't seem to be installed as a distro package. Looks ok to me."
   fi

fi

drun 'pip list'

exit 99


#
# yes. this will make the random number generator less secure. but remember this is for a honeypot
#

dlog "echo HRNGDEVICE=/dev/urandom > /etc/default/rnd-tools"

echo "HRNGDEVICE=/dev/urandom" > /etc/default/rnd-tools


if [ -f /etc/dshield.conf ] ; then
   dlog "dshield.conf found, content follows"
   drun cat /etc/dshield.conf
   chmod 600 /etc/dshield.conf
   outlog reading old configuration
   if grep -q 'uid=<authkey>' /etc/dshield.conf; then
      dlog "erasing <.*> pattern from dshield.conf"
      run sed -i.bak 's/<.*>//' /etc/dshield.conf
      dlog "modified content of dshield.conf follows"
      drun cat /etc/dshield.conf
   fi
   dlog "sourcing current dshield.conf but don't overwrite progdir in script ..."
   progdirold=$progdir
   . /etc/dshield.conf
   progdir=$progdirold
fi

exit 99

nomysql=0

dialog --title 'WARNING' --yesno "You are about to turn this Raspberry Pi into a honeypot. This software assumes that the device is dedicated to this task. There is no simple uninstall. Do you want to proceed?" 10 50
response=$?
case $response in
    ${DIALOG_CANCEL}) exit;;
esac


if [ -d /var/lib/mysql ]; then
  dialog --title 'Installing MySQL' --yesno "You may already have MySQL installed. Do you want me to re-install MySQL and erase all existing data?" 10 50
  response=$?
  case $response in 
      ${DIALOG_OK}) apt-get -y -qq purge mysql-server mysql-server-5.5 mysql-server-core-5.5;;
      ${DIALOG_CANCEL}) nomysql=1;;
      ${DIALOG_ESC}) exit;;
  esac
fi

if [ "$nomysql" -eq "0" ] ; then
mysqlpassword=`head -c10 /dev/random | xxd -p`
echo "mysql-server-5.5 mysql-server/root_password password $mysqlpassword" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password_again password $mysqlpassword" | debconf-set-selections
echo "mysql-server mysql-server/root_password password $mysqlpassword" | debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $mysqlpassword" | debconf-set-selections
apt-get -qq -y install mysql-server
cat > ~/.my.cnf <<EOF
[mysql]
user=root
password=$mysqlpassword
EOF
fi

if ! [ -d $TMPDIR ]; then
 exit
fi

# dialog --title 'DShield Installer' --menu "DShield Account" 10 40 2 1 "Use Existing Account" 2 "Create New Account" 2> $TMPDIR/dialog
# return_value=$?
# return=`cat $TMPDIR/dialog`

return_value=$DIALOG_OK
return=1

if [ $return_value -eq  $DIALOG_OK ]; then
    if [ $return = "1" ] ; then
	apikeyok=0
	while [ "$apikeyok" = 0 ] ; do
	    exec 3>&1
	    VALUES=$(dialog --ok-label "Verify" --title "DShield Account Information" --form "Authentication Information. Copy/Past from dshield.org/myaccount.html. Use CTRL-V to paste." 12 60 0 \
		       "E-Mail Address:" 1 2 "$email"   1 17 35 100 \
		       "       API Key:" 2 2 "$apikey" 2 17 35 100 \
		       2>&1 1>&3)

	      response=$?
	    exec 3>&-

	    case $response in 
		${DIALOG_OK}) 	    email=`echo $VALUES | cut -f1 -d' '`
	    apikey=`echo $VALUES | cut -f2 -d' '`
	    nonce=`openssl rand -hex 10`
	    hash=`echo -n $email:$apikey | openssl dgst -hmac $nonce -sha512 -hex | cut -f2 -d'=' | tr -d ' '`

	    user=`echo $email | sed 's/@/%40/'`
	    curl -s https://isc.sans.edu/api/checkapikey/$user/$nonce/$hash > $TMPDIR/checkapi

if ! [ -d "$TMPDIR" ]; then
  echo "can not find TMPDIR $TMPDIR"
  exit
fi

	    if grep -q '<result>ok</result>' $TMPDIR/checkapi ; then
		apikeyok=1;
		uid=`grep  '<id>.*<\/id>' $TMPDIR/checkapi | sed -E 's/.*<id>([0-9]+)<\/id>.*/\1/'`
            else
		dialog --title 'API Key Failed' --msgbox 'Your API Key Verification Failed.' 7 40
	    fi;;
		${DIALOG_CANCEL}) exit;;
		${DIALOG_ESC}) exit;;
esac;
	done

    fi
fi
echo $uid
dialog --title 'API Key Verified' --msgbox 'Your API Key is valid. The firewall will be configured next. ' 7 40


#
# Default Interface
#

# if we don't have one configured, try to figure it out
if [ "$interface" = "" ] ; then
interface=`ip link show | egrep '^[0-9]+: ' | cut -f 2 -d':' | tr -d ' ' | grep -v lo`
fi

# list of valid interfaces
validifs=`ip link show | grep '^[0-9]' | cut -f2 -d':' | tr -d '\n' | sed 's/^ //'`
localnetok=0

while [ $localnetok -eq  0 ] ; do
    exec 3>&1
    interface=$(dialog --title 'Default Interface' --form 'Default Interface' 10 40 0 \
		       "Honeypot Interface:" 1 2 "$interface" 1 25 10 10 2>&1 1>&3)
    exec 3>&-
    for b in $validifs; do
	if [ "$b" = "$interface" ] ; then
	    localnetok=1
	fi
    done
    if [ $localnetok -eq 0 ] ; then
	dialog --title 'Default Interface Error' --msgbox "You did not specify a valid interface. Valid interfaces are $validifs" 10 40
    fi
done
echo "Interface: $interface"

# figuring out local network.

ipaddr=`ip addr show  eth0 | grep 'inet ' |  awk '{print $2}' | cut -f1 -d'/'`
localnet=`ip route show | grep eth0 | grep 'scope link' | cut -f1 -d' '`
localnetok=0

while [ $localnetok -eq  0 ] ; do
    exec 3>&1
    localnet=$(dialog --title 'Local Network' --form 'Admin access will be restricted to this network, and logs originating from this network will not be reported.' 10 50 0 \
		      "Local Network:" 1 2 "$localnet" 1 25 20 20 2>&1 1>&3)

    exec 3>&-
    if echo "$localnet" | egrep -q '^([0-9]{1,3}\.){3}[0-9]{1,3}\/[0-9]{1,2}$'; then
	localnetok=1
    fi
    if [ $localnetok -eq 0 ] ; then
	dialog --title 'Local Network Error' --msgbox 'The format of the local network is wrong. It has to be in Network/CIDR format. For example 192.168.0.0/16' 40 10
    fi
done

# further IPs: no iptables logging

if [ "${nofwlogging}" == "" ] ; then
   # default: local net
   nofwlogging="${localnet}"
fi

exec 3>&1
NOFWLOGGING=$(dialog --title 'IPs to ignore in FW Log'  --cr-wrap --form "WARNING - USE WITH CARE!
IPs and nets the firewall should do no logging for (in notation iptables likes, separated by spaces).
Attention: entries will be added to use default policy for INPUT chain (ACCEPT) and the 'real' sshd will be exposed.
If unsure don't change anything here! Trusted IPs only. You have been warned.

" \
18 70 0 "Ignore FW Log:" 1 1 "${nofwlogging}" 1 25 40 100 2>&1 1>&3)
exec 3>&-

# for saving in dshield.conf
nofwlogging="'${NOFWLOGGING}'"

if [ "${NOFWLOGGING}" == "" ] ; then
   # echo "No firewall log exceptions will be done."
   dialog --title 'No Firewall Log Exceptions' --msgbox 'No firewall logging exceptions will be installed.' 10 40
else
   dialog --title 'Firewall Logging Exceptions' --cr-wrap --msgbox "The firewall logging exceptions will be installed for IPs
${NOFWLOGGING}." 20 60
fi


# further IPs: no honeypot

if [ "${nohoneyips}" == "" ] ; then
   # default: local net
   nohoneyips="${localnet}"
fi

if [ "${nohoneyports}" == "" ] ; then
   # default: cowrie ports
    nohoneyports="${HONEYPORTS}"
fi

exec 3>&1
NOHONEY=$(dialog --title 'IPs to disable Honeypot for'  --cr-wrap --form "WARNING - USE WITH CARE!
IPs and nets to disable honeypot for to prevent reporting internal legitimate failed access attempts (IPs / nets in notation iptables likes, separated by spaces / ports (not real but after PREROUTING) separated by spaces).
Attention: entries will be added to reject access to honeypot ports.
If unsure don't change anything here! Trusted IPs only. You have been warned.

" \
18 70 0 \
"IPs / Nets:" 1 1 "${nohoneyips}" 1 25 40 100  \
"Ports:" 2 1 "${nohoneyports}" 2 25 40 100 2>&1 1>&3)
exec 3>&-

# echo "###${NOHONEY}###"

NOHONEYIPS=`echo "${NOHONEY}"  | cut -d "
" -f 1`
NOHONEYPORTS=`echo "${NOHONEY}"  | cut -d "
" -f 2`

# echo "###${NOHONEYIPS}###"
# echo "###${NOHONEYPORTS}###"

if [ "${NOHONEYIPS}" == "" -o "${NOHONEYPORTS}" == "" ] ; then
   NOHONEYIPS=""
   NOHONEYPORTS=""
   # echo "No honeyport exceptions will be done."
   dialog --title 'No Honeypot Exceptions' --msgbox 'No honeypot exceptions will be installed.' 10 40
else
   dialog --title 'Honeypot Exceptions' --cr-wrap --msgbox "The honeypot exceptions will be installed for IPs
${NOHONEYIPS}
for ports ${NOHONEYPORTS}." 20 60
fi

# for saving in dshield.conf
nohoneyips="'${NOHONEYIPS}'"
nohoneyports="'${NOHONEYPORTS}'"


# create default firewall rule set
cat > /etc/network/iptables <<EOF

#
# 
#

*filter
:INPUT ACCEPT [0:0]
:FORWARD DROP [0:0]
:OUTPUT ACCEPT [0:0]
-A INPUT -i lo -j ACCEPT
-A INPUT -i $interface -m state --state ESTABLISHED,RELATED -j ACCEPT
EOF

# insert IPs and ports for which honeypot has to be disabled
# as soon as possible
if [ "${NOHONEYIPS}" != "" -a "${NOHONEYIPS}" != " " ] ; then
   echo "# START: IPs / Ports honeypot should be disabled for"  >> /etc/network/iptables
   # echo "###${NOFWLOGGING}###"
   for NOHONEYIP in ${NOHONEYIPS} ; do
      for NOHONEYPORT in ${NOHONEYPORTS} ; do
         echo "-A INPUT -i $interface -s ${NOHONEYIP} -p tcp --dport ${NOHONEYPORT} -j REJECT" >> /etc/network/iptables
      done
   done
   echo "# END: IPs / Ports honeypot should be disabled for"  >> /etc/network/iptables
# else
   # echo "n00b"
fi


cat >> /etc/network/iptables <<EOF
-A INPUT -i $interface -s $localnet -j ACCEPT
-A INPUT -i $interface -p tcp --dport 12222 -s 10.0.0.0/8 -j ACCEPT
-A INPUT -i $interface -p tcp --dport 12222 -s 192.168.0.0/8 -j ACCEPT
EOF

# insert to-be-ignored IPs just before the LOGging stuff so that traffic will be handled by default policy for chain
if [ "${NOFWLOGGING}" != "" -a "${NOFWLOGGING}" != " " ] ; then
   echo "# START: IPs firewall logging should be disabled for"  >> /etc/network/iptables
   # echo "###${NOFWLOGGING}###"
   for NOFWLOG in ${NOFWLOGGING} ; do
      echo "-A INPUT -i $interface -s ${NOFWLOG} -j RETURN" >> /etc/network/iptables
   done
   echo "# END: IPs firewall logging should be disabled for"  >> /etc/network/iptables
# else
   # echo "n00b"
fi


cat >> /etc/network/iptables <<EOF
-A INPUT -i $interface -j LOG --log-prefix " INPUT "
-A INPUT -i $interface -p tcp --dport 12222 -j DROP
COMMIT
*nat
:PREROUTING ACCEPT [0:0]
:INPUT ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:POSTROUTING ACCEPT [0:0]
-A PREROUTING -p tcp -m tcp --dport 22 -j REDIRECT --to-ports 2222
-A PREROUTING -p tcp -m tcp --dport 25 -j REDIRECT --to-ports 2525
-A PREROUTING -p tcp -m tcp --dport 80 -j REDIRECT --to-ports 8000

COMMIT
EOF
cp $progdir/../etc/network/if-pre-up.d/dshield /etc/network/if-pre-up.d
chmod 700 /etc/network/if-pre-up.d/dshield
sed -i.bak 's/^Port 22$/Port 12222/' /etc/ssh/sshd_config

if [ `grep "^Port 12222\$" /etc/ssh/sshd_config | wc -l` -ne 1 ] ; then
   dialog --title 'sshd port' --ok-label 'Yep, understood.' --cr-wrap --msgbox 'Congrats, you had already changed your sshd port to something other than 22.

Please clean up the mess and either
  - change the port manually to 12222
     in /etc/ssh/sshd_config OR
  - clean up the firewall rules and
     other stuff reflecting YOUR PORT (tm)' 13 50
fi

sed "s/%%interface%%/$interface/" < $progdir/../etc/rsyslog.d/dshield.conf > /etc/rsyslog.d/dshield.conf

# moving dshield stuff to target directory
# (don't like to have root run scripty which are not owned by root)
mkdir -p ${DSHIELDDIR}
cp $progdir/dshield.pl ${DSHIELDDIR}
chmod 700 ${DSHIELDDIR}/dshield.pl

#
# "random" offset for cron job so not everybody is reporting at once
#

offset1=`shuf -i0-29 -n1`
offset2=$((offset1+30));
cat > /etc/cron.d/dshield <<EOF
$offset1,$offset2 * * * * root ${DSHIELDDIR}/dshield.pl
EOF


#
# Update Configuration
#
if [ -f /etc/dshield.conf ]; then
    rm /etc/dshield.conf
fi

touch /etc/dshield.conf
chmod 600 /etc/dshield.conf
echo "uid=$uid" >> /etc/dshield.conf
echo "apikey=$apikey" >> /etc/dshield.conf
echo "email=$email" >> /etc/dshield.conf
echo "interface=$interface" >> /etc/dshield.conf
echo "localnet=$localnet" >> /etc/dshield.conf
echo "mysqlpassword=$mysqlpassword" >> /etc/dshield.conf
echo "mysqluser=root" >> /etc/dshield.conf
echo "version=$version" >> /etc/dshield.conf
echo "progdir=${DSHIELDDIR}" >> /etc/dshield.conf
echo "nofwlogging=$nofwlogging" >> /etc/dshield.conf
echo "nohoneyips=$nohoneyips" >> /etc/dshield.conf
echo "nohoneyports=$nohoneyports" >> /etc/dshield.conf

#
# creating srv directories
#

mkdir -p /srv/www/html
mkdir -p /var/log/mini-httpd
chmod 1777 /var/log/mini-httpd

#
# installing cowrie
#

wget -qO $TMPDIR/cowrie.zip https://github.com/micheloosterhof/cowrie/archive/master.zip
unzip -qq -d $TMPDIR $TMPDIR/cowrie.zip 

if [ ${?} -ne 0 ] ; then
   echo "Something went wrong downloading cowrie, ZIP corrupt."
   exit
fi

if [ -d /srv/cowrie ]; then
    rm -rf /srv/cowrie
fi
mv $TMPDIR/cowrie-master /srv/cowrie

ssh-keygen -t dsa -b 1024 -N '' -f /srv/cowrie/data/ssh_host_dsa_key > /dev/null

if ! grep '^cowrie:' -q /etc/passwd; then
    adduser --gecos "Honeypot,A113,555-1212,555-1212" --disabled-password --quiet --home /srv/cowrie --no-create-home cowrie
    echo Added user 'cowrie'
else
    echo User 'cowrie' already exists in OS. Making no changes
fi    

# check if cowrie db schema exists
x=`mysql -uroot -p$mysqlpassword -e 'select count(*) "" from information_Schema.schemata where schema_name="cowrie"'`
if [ $x -eq 1 ]; then
    echo "cowrie mysql database already exists. not touching it."
else
    # we create the database and call the creation script
    mysql -uroot -p$mysqlpassword -e 'create schema cowrie'
    mysql -uroot -p$mysqlpassword -e 'source /srv/cowrie/doc/sql/mysql.sql' cowrie
fi
if [ "$cowriepassword" = "" ]; then
    cowriepassword=`head -c10 /dev/random | xxd -p`
fi
echo cowriepassword=$cowriepassword >> /etc/dshield.conf

echo "Adding / updating cowrie user in MySQL."
cat <<EOF | mysql -uroot -p$mysqlpassword
   GRANT USAGE ON *.* TO 'cowrie'@'%' IDENTIFIED BY 'slfdjdsljfkjkjaibvjhabu76r3irbk';
   GRANT USAGE ON *.* TO 'cowrie'@'localhost' IDENTIFIED BY 'slfdjdsljfkjkjaibvjhabu76r3irbk';
   DROP USER 'cowrie'@'%';
   DROP USER 'cowrie'@'localhost';
   FLUSH PRIVILEGES;
   CREATE USER 'cowrie'@'localhost' IDENTIFIED BY '${cowriepassword}';
   GRANT ALL ON cowrie.* TO 'cowrie'@'localhost';
EOF



cp /srv/cowrie/cowrie.cfg.dist /srv/cowrie/cowrie.cfg
cat >> /srv/cowrie/cowrie.cfg <<EOF
[output_dshield]
userid = $uid
auth_key = $apikey
batch_size = 1
[output_mysql]
host=localhost
database=cowrie
username=cowrie
password=$cowriepassword
port=3306
EOF

sed -i.bak 's/svr04/raspberrypi/' /srv/cowrie/cowrie.cfg
sed -i.bak 's/^ssh_version_string = .*$/ssh_version_string = SSH-2.0-OpenSSH_6.7p1 Raspbian-5+deb8u1/' /srv/cowrie/cowrie.cfg

# make output of simple text commands more real

df > /srv/cowrie/txtcmds/bin/df
dmesg > /srv/cowrie/txtcmds/bin/dmesg
mount > /srv/cowrie/txtcmds/bin/mount
ulimit > /srv/cowrie/txtcmds/bin/ulimit
lscpu > /srv/cowrie/txtcmds/usr/bin/lscpu
echo '-bash: emacs: command not found' > /srv/cowrie/txtcmds/usr/bin/emacs
echo '-bash: locate: command not found' > /srv/cowrie/txtcmds/usr/bin/locate
chown -R cowrie:cowrie /srv/cowrie

# echo "###########  $progdir  ###########"

cp $progdir/../etc/init.d/cowrie /etc/init.d/cowrie
cp $progdir/../etc/logrotate.d/cowrie /etc/logrotate.d
cp $progdir/../etc/cron.hourly/cowrie /etc/cron.hourly
cp $progdir/../etc/cron.hourly/dshield /etc/cron.hourly
cp $progdir/../etc/mini-httpd.conf /etc/mini-httpd.conf
cp $progdir/../etc/default/mini-httpd /etc/default/mini-httpd

#
# Checking cowrie Dependencies
# see: https://github.com/micheloosterhof/cowrie/blob/master/requirements.txt
# ... and twisted dependencies: https://twistedmatrix.com/documents/current/installation/howto/optional.html
#

# format: <PKGNAME1>,<MINVERSION1>  <PKGNAME2>,<MINVERSION2>  <PKGNAMEn>,<MINVERSIONn>
#         meaning: <PGKNAME> must be installes in version >=<MINVERSION>
# if no MINVERSION: 0
# replace _ with -

# twisted v15.2.1 isn't working (problems with SSH key), neither is 17.1.0, so we use the latest version of 16 (16.6.0)

for PKGVER in twisted,16.6.0 cryptography,1.8.1 configparser,0 pyopenssl,16.2.0 gmpy2,0 pyparsing,0 packaging,0 appdirs,0 pyasn1-modules,0.0.8 attrs,0 service-identity,0 pycrypto,2.6.1 python-dateutil,0 tftpy,0 idna,0 pyasn1,0.2.3 ; do

   # echo "PKGVER: ${PKGVER}"

   PKG=`echo "${PKGVER}" | cut -d "," -f 1`
   VERREQ=`echo "${PKGVER}" | cut -d "," -f 2`
   VERREQLIST=`echo "${VERREQ}" | tr "." " "`

   VERINST=`pip show ${PKG} | grep "^Version: " | cut -d " " -f 2`

   if [ "${VERINST}" == "" ] ; then
      VERINST="0"
   fi

   VERINSTLIST=`echo "${VERINST}" | tr "." " "`

   # echo "PKG: ${PKG}"
   # echo "VERREQ: ${VERREQ}"
   # echo "VERREQLIST: ${VERREQLIST}"
   # echo "VERINST: ${VERINST}"
   # echo "VERINSTLIST: ${VERINSTLIST}"

   MUSTINST=0

   echo "+ checking cowrie dependency: module '${PKG}' ..."

   if [ "${VERINST}" == "0" ] ; then
      echo "  ERR: not found at all, will be installed"
      MUSTINST=1
      pip install ${PKG}
      if [ ${?} -ne 0 ] ; then
         echo "Error installing '${PKG}'. Aborting."
         exit 1
      fi
   else
      FIELD=1
      # check if version number of installed module is sufficient
      for VERNO in ${VERREQLIST} ; do
         # echo "FIELD: ${FIELD}"
         FIELDINST=`echo "${VERINSTLIST}" | cut -d " " -f "${FIELD}" `
         if [ "${FIELDINST}" == "" ] ; then
            FIELDINST=0
         fi
         FIELDREQ=`echo "${VERREQLIST}" | cut -d " " -f "${FIELD}" `
         if [ "${FIELDREQ}" == "" ] ; then
            FIELDREQ=0
         fi
         if [ ${FIELDINST} -lt ${FIELDREQ} ] ; then
            # first version string from left with lower number installed -> update
            MUSTINST=1
            break
         elif [ ${FIELDINST} -gt ${FIELDREQ} ] ; then
            # first version string from left with hight number installed -> done
            break
         fi
         FIELD=`echo "$((${FIELD} + 1))"`
      done
      if [ ${MUSTINST} -eq 1 ] ; then
         echo "  ERR: is installed in v${VERINST} but must at least be v${VERREQ}, will be updated"
         pip install ${PKG}==${VERREQ}
         if [ ${?} -ne 0 ] ; then
            echo "Error upgrading '${PKG}'. Aborting."
            exit 1
         fi
      fi
   fi

   # echo "MUSTINST: ${MUSTINST}"

   if [ ${MUSTINST} -eq 0 ] ; then
      echo "  OK: is installed in a sufficient version, nothing to do"
   fi


done


# setting up services
update-rc.d cowrie defaults
update-rc.d mini-httpd defaults

#
# installing postfix as an MTA
#

apt-get -y -qq purge postfix
echo "postfix postfix/mailname string raspberrypi" | debconf-set-selections
echo "postfix postfix/main_mailer_type select Internet Site" | debconf-set-selections
echo "postfix postfix/mynetwork string '127.0.0.0/8 [::ffff:127.0.0.0]/104 [::1]/128'" | debconf-set-selections
echo "postfix postfix/destinations string raspberrypi, localhost.localdomain, localhost" | debconf-set-selections
debconf-get-selections | grep postfix
apt-get -y -qq install postfix

#
# modifying motd
#

cat > $TMPDIR/motd <<EOF

The programs included with the Debian GNU/Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Debian GNU/Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.

***
***    DShield Honeypot - Web Admin on port 8080
***

EOF

mv $TMPDIR/motd /etc/motd

# checking certs
# if already there: ask if generate new

GENCERT=1

if [ `ls ../etc/CA/certs/*.crt 2>/dev/null | wc -l ` -gt 0 ]; then
   dialog --title 'Generating CERTs' --yesno "You may already have CERTs generated. Do you want me to re-generate CERTs and erase all existing ones?" 10 50
   response=$?
   case $response in
      ${DIALOG_OK}) 
         # cleaning up old certs
         rm ../etc/CA/certs/*
         rm ../etc/CA/keys/*
         rm ../etc/CA/requests/*
         rm ../etc/CA/index.*
         GENCERT=1
         ;;
      ${DIALOG_CANCEL}) 
         GENCERT=0
         ;;
      ${DIALOG_ESC}) exit;;
   esac
fi

if [ ${GENCERT} -eq 1 ] ; then
   ./makecert.sh
fi

echo
echo
echo Done. 
echo
echo "Please reboot your Pi now."
echo
echo "For feedback, please e-mail jullrich@sans.edu or file a bug report on github"
echo "Please include a sanitized version of /etc/dshield.conf in bug reports."
echo "To support logging to MySQL, a MySQL server was installed. The root password is $mysqlpassword"
echo
echo "IMPORTANT: after rebooting, the Pi's ssh server will listen on port 12222"
echo "           connect using ssh -p 12222 $SUDO_USER@$ipaddr"


