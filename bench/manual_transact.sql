insert into testfloat (num) values (floor(random() * 9999 + 1)::int);
select do_rollup('testfloat_rollup1');
