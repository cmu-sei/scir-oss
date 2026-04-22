typewriter()
{
  local _line="${1}"

  for _x in $(seq 0 ${#_line});
   do
   echo -n "${_line:${_x}:1}";
   sleep 0.15;
   done
echo
return
}

[[ ! -f "${1}" ]] && echo "no file ${1}" >&2

SCRIPTFILE="${1}"

sleep 2
while read -r _ln;
do
  typewriter "${_ln}"
  sleep 0.5
done < "${SCRIPTFILE}"

exit

sleep 2
typewriter "# now is the time"
sleep 2
typewriter "# for fun to start"
sleep 2
typewriter "date"
sleep 1
typewriter "exit"

