create or replace language plpython3u;
create extension if not exists pgrollup;

create table testfloat (
    id serial primary key,
    num bigint
);

create materialized view testfloat_rollup1 as (
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

