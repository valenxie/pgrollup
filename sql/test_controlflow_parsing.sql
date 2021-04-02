SET client_min_messages TO WARNING;
create or replace language plpython3u;
create extension if not exists pg_rollup;

create temporary table testparsing (
    id serial primary key,
    name text,
    num int
);

insert into testparsing (name,num) values
    ('alice', 1),
    ('alice', 2),
    ('alice', 3),
    ('alice', 4),
    ('alice', 5),
    ('bill', 5),
    ('bill', 5),
    ('bill', 5),
    ('charlie', 1),
    ('charlie', 1),
    ('charlie', 1),
    ('charlie', 3),
    ('charlie', NULL),
    ('dave', 4),
    ('elliot', 5),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 8),
    (NULL, 9),
    (NULL, NULL),
    (NULL, NULL),
    (NULL, NULL),
    (NULL, NULL);

select pgrollup($$
CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup1 AS (
    SELECT
        count(*) AS count
    FROM testparsing
    GROUP BY name
);

CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup2 AS (
    select count(*) AS count
    from testparsing
    group by name,num
);

CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup3 AS (
    select
        sum(num) AS sum,
        count(*) AS count_all,
        count(num),
        max(num),
        min(num)
    from testparsing
    group by name
);

CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup4 AS (
    select
        sum(num) AS sum,
        count(*) AS count_all,
        count(num),
        max(num),
        min(num)
    from testparsing
);
$$);

select pgrollup($$
CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup5 AS (
    select
        max(num),
        count(*) - sum(num) AS foo 
    from testparsing
);
$$);

select pgrollup($$
CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup6 AS (
    select
        max(num),
        sum(num)/count(num) as avg,
        max(num) - min(num) as range,
        max(num)-max(num)+max(num)-max(num)+55
    from testparsing
);
$$);

select pgrollup($$
CREATE INCREMENTAL MATERIALIZED VIEW testparsing_rollup7 AS (
    select
        sum(num*num + 2),
        max(1),
        (max((1 + (((num))))*2) + count(num))/count(*)
        + (max((1 + (((num))))*2) + count(num))/count(*)
    from testparsing
);
$$);

select * from testparsing_rollup5;
select * from testparsing_rollup5_raw;

select assert_rollup('testparsing_rollup1');
select assert_rollup('testparsing_rollup2');
select assert_rollup('testparsing_rollup3');
select assert_rollup('testparsing_rollup4');
select assert_rollup('testparsing_rollup5');
select assert_rollup('testparsing_rollup6');
select assert_rollup('testparsing_rollup7');

insert into testparsing (name,num) values
    ('alice', 1),
    ('alice', 2),
    ('alice', 3),
    ('alice', 4),
    ('alice', 5),
    ('bill', 5),
    ('bill', 5),
    ('bill', 5),
    ('charlie', 1),
    ('charlie', 1),
    ('charlie', 1),
    ('charlie', 3),
    ('charlie', NULL),
    ('dave', 4),
    ('elliot', 5),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 1),
    (NULL, 8),
    (NULL, 9),
    (NULL, NULL),
    (NULL, NULL),
    (NULL, NULL),
    (NULL, NULL);

select assert_rollup('testparsing_rollup1');
select assert_rollup('testparsing_rollup2');
select assert_rollup('testparsing_rollup3');
select assert_rollup('testparsing_rollup4');
select assert_rollup('testparsing_rollup5');
select assert_rollup('testparsing_rollup6');
select assert_rollup('testparsing_rollup7');
