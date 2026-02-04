#!/bin/bash
#Login with ssh key and change the root password 
#before execution:
#Void .ssh/known_hosts file: > ~/.ssh/known_hosts ; Void also RESULT_FILE, if it exists.
#Authenticate to mfaconnect/

##Begin Prerequisites##
if [ -z "$1" ]
then
	echo "Usage: $(basename $0) HOST_LIST.txt" 
	echo "Example: $(basename $0) host_list.txt"
	exit 1
else
	HOST_LIST="$1"
fi

#Verify that it runs in a tmux session
if ! env | grep -q TMUX
then
    echo -e "Pleas open a tmux session \n Bye"
    exit 1
fi

read -p "Did you authenticate to mfaconnect ?  [y/N]: " ANSWER
if  [[ $ANSWER !=  [yY] ]]
then
    echo "Please authenticate to mfaconnect, if needed"
    echo "Bye"
    exit 1
fi
##End Prerequisites##

RESULT_FILE=${HOST_LIST%.*}_$(date +%F).csv
NEW_PASS='*****'		#Set the desired new password here
PASSWORDLIST=('Pass1' 'Pass2' 'Pass3' 'Pass4' 'Pass5' 'Pass6')  
USER=root
REMOTECMD="echo '$NEW_PASS' | passwd --stdin $USER" 				#This is the solution for problematic passwords
TIMEOUT=90
CTIMEOUT=10

truncate -s 0 ~/.ssh/known_hosts

singleHost (){
	#Test if the new password has already been setup
	SSH_OUTPUT=$(timeout $TIMEOUT sshpass -p $NEW_PASS ssh -n -o LogLevel=INFO -o ConnectTimeout=$CTIMEOUT -o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o PubkeyAuthentication=no  $USER@${HOST} "uname" 2>&1)
	RC=$?
	case $RC in
		0)
			echo "Password ok"
			SSH_OUTPUT="ok"
			echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			;;

		124)
			echo "Timedout"
			echo $HOST,$RC,'timeout' command timed out | tee -a $RESULT_FILE
			;;

		255)
			echo "ssh failed"
			SSH_OUTPUT=$(grep -Eo 'Permission denied|Connection timed out|Connection refused|Could not resolve hostname|Unable to negotiate|Connection closed|No route to host|Connection reset' <<< $SSH_OUTPUT)

			#'Permission denied' means that the server is preventing password usage so try connecting with ssh key.
			if [[ $SSH_OUTPUT == "Permission denied" ]] && SSH_OUTPUT=$(timeout $TIMEOUT  ssh -n -o LogLevel=INFO -o ConnectTimeout=$CTIMEOUT -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o PubkeyAuthentication=yes -o BatchMode=yes  $USER@${HOST} "$REMOTECMD" 2>&1)
			then
				RC=$?
				SSH_OUTPUT="$(grep -o 'updated successfully' <<< $SSH_OUTPUT) (Key)"
				echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			else
				#echo "Key failed"
#				SSH_OUTPUT="Password not allowed"
				echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			fi
			#echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			;;

		5)
			echo "Incorrect password, trying key"
			#Try connecting with ssh key
			if SSH_OUTPUT=$(timeout $TIMEOUT  ssh -n -o LogLevel=INFO -o ConnectTimeout=$CTIMEOUT -o StrictHostKeyChecking=no -o PasswordAuthentication=no -o PubkeyAuthentication=yes $USER@${HOST} "$REMOTECMD" 2>&1)
			then
				RC=$?
				SSH_OUTPUT="$(grep -o 'updated successfully' <<< $SSH_OUTPUT) (Key)"
				echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			else	
			#	echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
				echo "Key failed"
				passwordAuthenticate &
			fi
			;;

		*)
			echo "Something Else"
			echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
			;;
	esac
}

passwordAuthenticate (){
#Try old/known passwords	
echo "Trying password list"
        for (( i=0  ; i<${#PASSWORDLIST[@]} ; ++i ))
        do
		if SSH_OUTPUT=$(timeout $TIMEOUT sshpass -p ${PASSWORDLIST[i]} ssh -n -o LogLevel=INFO -o ConnectTimeout=$CTIMEOUT -o StrictHostKeyChecking=no -o PasswordAuthentication=yes -o PubkeyAuthentication=no  $USER@${HOST} "$REMOTECMD" 2>&1)
		then 
			RC=$?
			echo -e "Password ${PASSWORDLIST[i]:0:2}****** succeeded"
			SSH_OUTPUT="$(grep -o 'updated successfully' <<< $SSH_OUTPUT) (Pass)"
			echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
                	return 0
            	else
			RC=$?
			echo -e "Password ${PASSWORDLIST[i]:0:2}****** failed :-("
            	fi
        done
		SSH_OUTPUT="Password list failed"
		echo $HOST,$RC,$SSH_OUTPUT | tee -a $RESULT_FILE
}

#-----------------------------------------------------------------------------------

COUNTER=0
while IFS=',' read  HOST ETC
do
	((++COUNTER))
	echo -e "\n#$COUNTER SSHing $HOST with new Password"
	singleHost $HOST &
done < $HOST_LIST 

# ©2023 Written by Golan Durany - Unix Delivery
