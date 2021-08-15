psql -c "CREATE DATABASE temp"

count=$1
mode=$2
# create a new init.sql with $count rollup tables inside of it
base_code='
create table testfloat (
    id serial primary key,
    num bigint
);   
'

extension='
create or replace language plpython3u;
create extension if not exists pgrollup;
'

event="
CREATE EVENT TRIGGER pgrollup_from_matview_trigger ON ddl_command_end WHEN TAG IN ('CREATE MATERIALIZED VIEW') EXECUTE PROCEDURE pgrollup_from_matview_event();
"

temp_file=$(mktemp initXXX --suffix ".sql")
echo  "$extension""$event""$base_code" > $temp_file

for i in $(seq 1 $count); do
    lbl=$i
    rollup_code="
    create materialized view testfloat_rollup$lbl as (
    select
        count(num),
        avg(num),
        var_pop(num),
        var_samp(num),
        variance(num),
        stddev(num),
        stddev_pop(num),
        stddev_samp(num)
    from testfloat
    );  
    "
    rollup_mode="select rollup_mode('testfloat_rollup$lbl','$mode');"
    echo "$rollup_code""$rollup_mode" >> $temp_file
done

echo "$rollup_mode" >> $temp_file

psql -d temp -c "\i $temp_file"

if [ $mode = "trigger" ];then
    tps=$(pgbench -f bench/transact.sql -n temp | grep "(including connections establishing)" | cut -f 2 -d "=" | grep -Eo '[0-9]+([.][0-9]+)?+')
    echo $count,$tps,$mode >> bench/tbl_data.csv
else
    tps=$(pgbench -f bench/manual_transact.sql -n temp | grep "(including connections establishing)" | cut -f 2 -d "=" | grep -Eo '[0-9]+([.][0-9]+)?+')
    echo $count,$tps,$mode >> bench/manual_tbl_data.csv
fi 

psql -c "DROP DATABASE temp"
    
