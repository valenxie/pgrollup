psql -c "CREATE DATABASE temp"

count=$1
mode=$2

extension='
create or replace language plpython3u;
create extension if not exists pgrollup;
'

event="
CREATE EVENT TRIGGER pgrollup_from_matview_trigger ON ddl_command_end WHEN TAG IN ('CREATE MATERIALIZED VIEW') EXECUTE PROCEDURE pgrollup_from_matview_event();
"

base_code='
create table testfloat (
    id serial primary key,
    num bigint
);   
'

temp_file=$(mktemp initXXX --suffix ".sql")
echo "$extension""$event""$base_code" > $temp_file
rollup_code='create materialized view testfloat_rollup1 as ( select'
lbl='1'
for i in $(seq 1 $count); do
    lbl=$i
    if [ $i -eq $count ]
    then
        rollup_code="$rollup_code count(num) as count$lbl"
    else
        rollup_code="$rollup_code count(num) as count$lbl,"
    fi
done

rollup_code="$rollup_code from testfloat);"

rollup_mode="select rollup_mode('testfloat_rollup1','$mode');"

echo "$rollup_code" >> $temp_file
echo "$rollup_mode" >> $temp_file

psql -d temp -c "\i $temp_file"

echo "temp file is:$temp_file"

if [ $mode = "trigger" ]; then
    tps=$(pgbench -f bench/transact.sql -n temp | grep "(including connections establishing)" | cut -f 2 -d "=" | grep -Eo '[0-9]+([.][0-9]+)?+')
    echo $count,$tps,$mode >> bench/col_data.csv
else
    tps=$(pgbench -f bench/manual_transact.sql -n temp | grep "(including connections establishing)" | cut -f 2 -d "=" | grep -Eo '[0-9]+([.][0-9]+)?+')
    echo $count,$tps,$mode >> bench/manual_col_data.csv
fi

psql -c "DROP DATABASE temp"
