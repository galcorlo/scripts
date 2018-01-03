#!/bin/bash
# Manage large ACL from Cisco devices for example.
# After you modify ACL, this script will paste it in small chunks via ssh

# Done for tmux 1.1
# With a higher tmux version we could user load-buffer with names and wait-for to wait after connecting to switch

TMP_PATH=/tmp
CHUNK_SIZE_LINES=500
ALEATORI=$(date +%s | sha256sum | base64 | head -c 32)
TMUX_SESSION=MANAGE_ACL_${USER}_${ALEATORI}
SPLITED_FILE=${TMP_PATH}/${ALEATORI}${USER}
ACL_FILE=$1
ACL_PATH=/opt/capirca/filters
USUARI=${2:-gerard.alcorlo}
DEVICE=${3:-sw6506-core}
CONTRASENYA='per defecte'

set -e
set -u

if [ "$#" -lt 1 ]; then
  echo -e "\n   Usage example: \n\n   $0  ACL-FILE.acl  gerard.alcorlo  [switch-device]\n"
  exit 1
fi


function paste_acl {
# paste buffers sequentially
#   tmux select-pane -t 0
   I=1
   echo "Pasting lines from 0 to $CHUNK_SIZE_LINES of $TOTAL_LINES"
   tmux send-keys -t 0 "term width 200" C-m
   tmux send-keys -t 0 "conf t" C-m

   while [ $CHUNKS -gt 0 ]; do
      tmux select-pane -t 0
      tmux paste-buffer -db 0 -t 0
      let CHUNKS=CHUNKS-1
      
      tmux select-pane -t 1
      echo -e "Press [ENTER] when you see \e[4m\e[1mChunk pasted. Press [ENTER] to paste next chunk...\e[0m at the top window to continue\n"
      let I=I+1

      if [ $CHUNKS -ne 0 ]; then
         if [ $(( $CHUNK_SIZE_LINES*$I )) -le $TOTAL_LINES ]; then
            read -s ignore
            echo "Pasting from line $(( $CHUNK_SIZE_LINES*($I-1) )) to $(( $CHUNK_SIZE_LINES*$I )) of $TOTAL_LINES"
         else
            echo "Pasting from line $(( $CHUNK_SIZE_LINES*($I-1) )) to $TOTAL_LINES"
         fi
      fi
   done

   echo -e "\n\nCheck if the ACL is ok and save the config to flash card writing, \e[4m\e[1mwr mem\e[0m to switch pane"
   echo -e "\n\nPress enter to close this pane or write \e[4m\e[1mskip\e[0m to keep this pane open: "
   read info

   if [ "$info" != 'skip' ]; then
      tmux send-keys -t 1 "exit" C-m
   fi
}

export -f paste_acl

tmux new -s $TMUX_SESSION -d
tmux set-option -g -t $TMUX_SESSION buffer-limit 10000 > /dev/null
tmux set-option -g -t $TMUX_SESSION history-limit 2000 > /dev/null

# split big acl into small files
TOTAL_LINES=$(wc -l ${ACL_PATH}/${ACL_FILE} | egrep -o '^[0-9]+')
split -l ${CHUNK_SIZE_LINES} -d ${ACL_PATH}/${ACL_FILE} ${SPLITED_FILE}

# append comments to every chunk
for file in `ls -1 ${SPLITED_FILE}* | head -n -1`; do
   echo -e "! \n! \n! \n! Chunk pasted. Press [ENTER] to paste next chunk..." >> $file
done

echo -e "! \n! \n! \n! Last Chunk pasted. If you think everything is ok save the config." >> $(ls -1 ${SPLITED_FILE}* | tail -1)

# load splited files to tmux buffers. It's an stack and the last loadded buffer is the 0.
# tmux load-buffer -b ${file##$TMP_PATH/} $file  //not supported on this version
CHUNKS=0
for file in `find $TMP_PATH -maxdepth 1 -type f -wholename $SPLITED_FILE\* | sort -rn`; do
   tmux load-buffer $file
   let CHUNKS=CHUNKS+1
done
tmux set-environment -t $TMUX_SESSION CHUNKS $CHUNKS
tmux set-environment -t $TMUX_SESSION TOTAL_LINES $TOTAL_LINES
tmux set-environment -t $TMUX_SESSION CHUNK_SIZE_LINES $CHUNK_SIZE_LINES

# delete splited files from tmp
rm ${SPLITED_FILE}*

# connect to switch
tmux select-pane -t "$TMUX_SESSION:0.0"
tmux send-keys -t "$TMUX_SESSION:0.0" "ssh -oStrictHostKeyChecking=no $DEVICE -l $USUARI" C-m

tmux split-window -v 

echo -ne "\e[1mssh ${USUARI}@${DEVICE}\e[0m  connecting..."
sleep 2
echo ""
read -sp "Password: " CONTRASENYA

# loggin to switch
tmux send-keys -t "$TMUX_SESSION:0.0" "$CONTRASENYA" C-m
sleep 2

tmux send-keys -t "$TMUX_SESSION:0.1" "paste_acl" C-m
tmux attach-session -t $TMUX_SESSION 
