\echo Use "CREATE EXTENSION pg_rollup" to load this file. \quit


/*
CREATE OR REPLACE FUNCTION hll_hash_anynull(a anyelement) RETURNS hll_hashval AS $$
    SELECT COALESCE(hll_hash_any(a), 0::hll_hashval);
$$ LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

do $$
BEGIN
    assert( hll_hash_anynull(null::integer) = 0::hll_hashval);
    assert( hll_hash_anynull(null::text) = 0::hll_hashval);
    assert( hll_hash_anynull(123) = hll_hash_any(123));
    assert( hll_hash_anynull('123'::text) = hll_hash_any('123'::text));
END;
$$;
*/


CREATE OR REPLACE FUNCTION array_uniq(a anyarray) RETURNS anyarray AS $$
SELECT ARRAY(SELECT DISTINCT unnest(a));
$$ LANGUAGE 'sql' STRICT IMMUTABLE PARALLEL SAFE;

do $$
BEGIN
    assert( array_uniq('{}'::INT[]) = '{}');
    assert( array_uniq('{1,1,1,1}'::INT[]) = '{1}');
    assert( array_uniq('{1,1,2,3}'::INT[]) = '{1,2,3}');
    assert( array_uniq('{1,2,3,1}'::INT[]) = '{1,2,3}');
    assert( array_uniq('{NULL,NULL}'::INT[]) = '{NULL}');
    assert( array_uniq(NULL::INT[]) IS NULL);
END;
$$;


--------------------------------------------------------------------------------

CREATE TABLE algebras (
    id                      SERIAL PRIMARY KEY,
    name                    TEXT NOT NULL,
    agg                     TEXT NOT NULL,
    type                    TEXT NOT NULL,
    zero                    TEXT NOT NULL,
    plus                    TEXT NOT NULL,
    negate                  TEXT,
    view                    TEXT
);

-- FIXME:
-- add support for automatically adding dependent columns
-- inserting null values can mess things up, especially when it's the first value inserted
INSERT INTO algebras
    (name       ,agg                            ,type       ,zero                       ,plus                           ,negate ,view)
    VALUES
    ('count'    ,'count(x)'                     ,'INTEGER'  ,'0'                        ,'count(x)+count(y)'            ,'-x'   ,'x'),
    ('sum'      ,'sum(x)'                       ,'x'        ,'0'                        ,'sum(x)+sum(y)'                ,'-x'   ,'x'),
    ('min'      ,'min(x)'                       ,'x'        ,'null'                     ,'least(min(x),min(y))'         ,NULL   ,'x'),
    ('max'      ,'max(x)'                       ,'x'        ,'null'                     ,'greatest(max(x),max(y))'      ,NULL   ,'x'),
    ('topn'     ,'topn_add_agg(x)'              ,'JSONB'    ,$$'{}'$$                   ,'topn_union(topn(x),topn(y))'  ,NULL   ,'topn(x,1)'),
    ('hll'      ,'hll_add_agg(hll_hash_any(x))' ,'hll'      ,'hll_empty()'              ,'hll(x)||hll(y)'               ,NULL   ,'floor(hll_cardinality(x))');

INSERT INTO algebras
    (name       ,agg                            ,type       ,zero                       ,plus                           ,negate ,view)
    VALUES
    ( 'avg'
    , 'avg(x)'
    , 'FLOAT'
    , '0'
    , 'avg(x)*(count(x)/(count(x)+count(y))::FLOAT)+avg(y)*(count(y)/(count(x)+count(y))::FLOAT)'
    , 'x'
    , 'x'
    ),
    ( 'var_pop'
    , 'var_pop(x)'
    , 'FLOAT'
    , '0'
    , '(count(x)/(count(x)+count(y)::FLOAT))*(var_pop(x)+(avg(x) - count(x)/(count(x)+count(y)::FLOAT)*avg(x) - count(y)/(count(x)+count(y)::FLOAT)*avg(y))^2) + (count(y)/(count(x)+count(y)::FLOAT))*(var_pop(y)+(avg(y) - count(y)/(count(x)+count(y)::FLOAT)*avg(y) - count(x)/(count(x)+count(y)::FLOAT)*avg(x))^2)'
    , 'x'
    , 'x'
    ),
    ( 'var_samp'
    , 'coalesce(var_samp(x),0)'
    --, 'var_samp(x)'
    , 'FLOAT'
    , '0'
    --, 'CASE (count(x)+count(y)) WHEN 0 THEN 0 ELSE CASE (count(x)+count(y)-1) WHEN 0 THEN 0 ELSE (count(x)/(count(x)+count(y)-1::FLOAT))*(((count(x)-1)/(count(x)::FLOAT))*var_samp(x)+(avg(x) - count(x)/(count(x)+count(y)::FLOAT)*avg(x) - count(y)/(count(x)+count(y)::FLOAT)*avg(y))^2) + (count(y)/(count(x)+count(y)-1::FLOAT))*(((count(y)-1)/(count(y)::FLOAT))*var_samp(y)+(avg(y) - count(y)/(count(x)+count(y)::FLOAT)*avg(y) - count(x)/(count(x)+count(y)::FLOAT)*avg(x))^2) END END'
    , '(count(x)/(count(x)+count(y)-1::FLOAT))*(((count(x)-1)/(count(x)::FLOAT))*var_samp(x)+(avg(x) - count(x)/(count(x)+count(y)::FLOAT)*avg(x) - count(y)/(count(x)+count(y)::FLOAT)*avg(y))^2) + (count(y)/(count(x)+count(y)-1::FLOAT))*(((count(y)-1)/(count(y)::FLOAT))*var_samp(y)+(avg(y) - count(y)/(count(x)+count(y)::FLOAT)*avg(y) - count(x)/(count(x)+count(y)::FLOAT)*avg(x))^2)'
    , 'x'
    , 'x'
    );

    --('hll'      ,'hll_add_agg(x)'  ,'hll'      ,'hll_hash_any(x)'  ,'hll_empty()'  ,'x||y'             ,NULL   ,'floor(hll_cardinality(x))');
    --('tdigest'  ,'tdigest(x,100)'               ,'tdigest'  ,'null'         ,'greatest(x,y)'    ,NULL   ,'tdigest_percentile(x,0.50)'),
    
    /*

    bit_and
    bit_or
    bool_and
    bool_or

    https://pgxn.org/dist/datasketches/1.2.0/
    https://github.com/tvondra/tdigest

    stddev
    higher order moments?
    https://madlib.apache.org/docs/master/group__grp__sketches.html
    https://github.com/ozturkosu/cms_topn  <-- doesn't build on postgres:12,10
    OLS
    convex optimizations / online learning
    */


--------------------------------------------------------------------------------

CREATE TABLE pg_rollup (
    rollup_name TEXT PRIMARY KEY,
    table_name TEXT NOT NULL,
    event_id_sequence_name TEXT,
    rollup_column TEXT,
    sql TEXT NOT NULL,
    mode TEXT NOT NULL,
    last_aggregated_id BIGINT DEFAULT 0
);

CREATE TABLE pg_rollup_settings (
    name TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
INSERT INTO pg_rollup_settings (name,value) VALUES
    ('default_mode','trigger');

/*
 * The pg_rollup table should contain one row per rollup;
 * this event trigger ensures that the row gets deleted when the rollup gets dropped.
 * FIXME:
 * This trigger doesn't seem to fire when a temporary table is automatically dropped at the end of a session.
 * This can result in a table_name erroneously still existing in the pg_rollup table.
 */
CREATE OR REPLACE FUNCTION pg_rollup_drop_function()
RETURNS event_trigger AS $$
DECLARE
    obj record;
BEGIN
    IF tg_tag LIKE 'DROP%'
    THEN
        FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
        LOOP
            DELETE FROM pg_rollup WHERE table_name=obj.object_name;
        END LOOP;
    END IF;
END;
$$ LANGUAGE plpgsql;
CREATE EVENT TRIGGER pg_rollup_drop_trigger ON sql_drop EXECUTE PROCEDURE pg_rollup_drop_function();


/*
 * Manual rollup functions modified from
 * https://www.citusdata.com/blog/2018/06/14/scalable-incremental-data-aggregation/
 *
 * The incremental_rollup_window function has been modified so that it doesn't
 * rollup the entire table at once, but in smaller chuncks;
 * this is useful for rolling up large tables incrementally that have already been created
 */
CREATE FUNCTION incremental_rollup_window(
    rollup_name text, 
    max_rollup_size bigint default 4611686018427387904, -- 2**62
    force_safe boolean default true,
    OUT window_start bigint,
    OUT window_end bigint
)
RETURNS record
LANGUAGE plpgsql
AS $function$
DECLARE
    table_to_lock regclass;
BEGIN
    /*
     * Perform aggregation from the last aggregated ID + 1 up to the last committed ID.
     * We do a SELECT .. FOR UPDATE on the row in the rollup table to prevent
     * aggregations from running concurrently.
     */
    SELECT table_name, last_aggregated_id+1, LEAST(last_aggregated_id+max_rollup_size+1,pg_sequence_last_value(event_id_sequence_name))
    INTO table_to_lock, window_start, window_end
    FROM pg_rollup
    WHERE pg_rollup.rollup_name = incremental_rollup_window.rollup_name FOR UPDATE;

    IF NOT FOUND THEN
        RAISE 'rollup ''%'' is not in the pg_rollup table', rollup_name;
    END IF;

    IF window_end IS NULL THEN
        /* sequence was never used */
        window_end := 0;
        RETURN;
    END IF;

    /*
     * Play a little trick: We very briefly lock the table for writes in order to
     * wait for all pending writes to finish. That way, we are sure that there are
     * no more uncommitted writes with a identifier lower or equal to window_end.
     * By throwing an exception, we release the lock immediately after obtaining it
     * such that writes can resume.
     */
    IF force_safe THEN
        BEGIN
            -- NOTE: The line below is modified from the original to acquire
            -- a ROW EXCLUSIVE lock rather than an exclusive lock; this lock still
            -- prevents update/insert/delete operations on the table, but it does
            -- not block on autovacuum (SHARE UPDATE EXCLUSIVE lock) or
            -- create index (SHARE lock).  I believe everything is therefore still
            -- correct, but this is magic beyond my domain expertise, so I'm
            -- not 100% certain.
            EXECUTE format('LOCK %s IN ROW EXCLUSIVE MODE', table_to_lock);
            RAISE 'release table lock';
        EXCEPTION WHEN OTHERS THEN
        END;
    END IF;

    /*
     * Remember the end of the window to continue from there next time.
     */
    UPDATE pg_rollup SET last_aggregated_id = window_end WHERE pg_rollup.rollup_name = incremental_rollup_window.rollup_name;
END;
$function$;


CREATE FUNCTION do_rollup(
    rollup_name text,
    max_rollup_size bigint default 4611686018427387904, -- 2**62
    force_safe boolean default true,
    delay_seconds integer default 0,
    OUT start_id bigint, 
    OUT end_id bigint
)
RETURNS record
LANGUAGE plpgsql
AS $function$
DECLARE
    sql_command text;
    mode text;
BEGIN
    /* if the rollup is in trigger mode, then there is nothing to update, so we do nothing */
    SELECT pg_rollup.mode INTO mode FROM pg_rollup WHERE pg_rollup.rollup_name=do_rollup.rollup_name;
    IF mode != 'trigger' THEN

        PERFORM pg_sleep(delay_seconds);

        /* determine which page views we can safely aggregate */
        SELECT window_start, window_end INTO start_id, end_id
        FROM incremental_rollup_window(rollup_name,max_rollup_size,force_safe);

        /* exit early if there are no new page views to aggregate */
        IF start_id > end_id THEN RETURN; END IF;

        /* this is the new code that gets the rollup command from the table
         * and executes it */
        SELECT pg_rollup.sql 
        INTO sql_command
        FROM pg_rollup 
        WHERE pg_rollup.rollup_name = do_rollup.rollup_name;

        EXECUTE 'select '||sql_command||'($1,$2)' USING start_id,end_id;
    END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION assert_rollup(rollup_name REGCLASS)
RETURNS VOID AS $$
    sql = f'select * from {rollup_name}_groundtruth except select * from {rollup_name};';
    res = plpy.execute(sql)
    assert len(res)==0
    sql = f'select * from {rollup_name} except select * from {rollup_name}_groundtruth;';
    res = plpy.execute(sql)
    assert len(res)==0
$$
LANGUAGE plpython3u
RETURNS NULL ON NULL INPUT;


CREATE OR REPLACE FUNCTION create_rollup(
    table_name  REGCLASS,
    rollup_name TEXT,
    tablespace TEXT DEFAULT 'pg_default', -- FIXME: set to NULL
    wheres TEXT DEFAULT '',
    rollups TEXT DEFAULT 'count(*) as count',
    key TEXT DEFAULT NULL,
    mode TEXT DEFAULT NULL
    )
RETURNS VOID AS $$
    import pg_rollup
    import re
    import collections

    def process_list(ks, error_str, parse_algebra=False):
        '''
        converts postgresql strings of either of the following forms
            value
            value AS name
        into python pg_rollup.Key values with a value, type, and name;
        this function is responsible for the vast majority of error handling,
        and the error messages could still probably be improved considerably
        '''
        ret = []
        for k in ks:
            if not parse_algebra:
                # extract the value from the input,
                # and if the 'AS' syntax is used, also extract the name
                l,_,r = k.rpartition('AS ')
     
                # case when AS does not apper in the input string
                if l=='': 
                    value = k.strip()
                    name = None

                # when AS appears in the input string,
                # but the contents to the right of AS are not a valid column name;
                # we treat the input as not using the AS syntax
                elif not re.match(r'^\w+$', r.strip()): 
                    value = k.strip()
                    name = None

                # the AS syntax was used correctly
                else:
                    value = l.strip()
                    name = r.strip()
                algebra = 'hll'
            else:
                # FIXME: move the logic above into the parse_algebra function
                d = pg_rollup.parse_algebra(k)
                value = d['expr']
                name = d['name']
                algebra = d['algebra']

            # extract the type and a default name from the value
            sql = f'select {value} from {table_name} limit 1;'
            res = plpy.execute(sql)
            t_oid = res.coltypes()[0]
            name = name or res.colnames()[0]

            sql = f'select typname from pg_type where oid={t_oid} limit 1;'
            type = plpy.execute(sql)[0]['typname']

            # if the name has a ? inside of it, it will not be a valid name, so we through an error;
            # this occurs when no name is specified, and postgresql cannot infer a good name for the column
            if '?' in name:
                plpy.error(f'invalid name for {error_str}: {k}, consider using the syntax: {k} AS column_name')

            # the value/type/name have been successfully extracted,
            # and so we add them to the ret variable
            sql = f"select * from algebras where name='{algebra}';"
            algebra_dictionary = plpy.execute(sql)[0]
            ret.append(pg_rollup.Key(value,type,name,algebra_dictionary))

        # if there are any duplicate names, throw an error
        names = [k.name for k in ret]
        duplicate_names = [item for item, count in collections.Counter(names).items() if count > 1]
        if len(duplicate_names) > 0:
            plpy.error(f'duplicate names in {error_str}: '+str(duplicate_names))

        # everything worked without error, so return
        return ret

    # if no mode provided, calculate the default mode
    global mode
    if mode is None:
        mode = plpy.execute("select value from pg_rollup_settings where name='default_mode';")[0]['value'];
        if mode is None:
            mode = 'trigger'

    # if no tablespace provided, calculate the default tablespace
    global tablespace
    if tablespace is None:
        tablespace_name = plpy.execute('show default_tablespace;')[0]['default_tablespace'];
        if tablespace_name is None:
            tablespace_name = 'pg_default'
    else:
        tablespace_name = tablespace

    # extract a list of wheres and rollups from the input parameters
    wheres_list = pg_rollup._extract_arguments(wheres)
    if len(wheres_list)==1 and wheres_list[0].strip()=='':
        wheres_list=[]

    rollups_list = pg_rollup._extract_arguments(rollups)
    if len(rollups_list)==1 and rollups_list[0].strip()=='':
        rollups_list=[]

    # check if the table is temporary
    sql = f"SELECT relpersistence='t' as is_temp FROM pg_class where relname='{table_name}'"
    is_temp = plpy.execute(sql)[0]['is_temp']

    # constuct the sql statements for generating the rollup, and execute them
    # the error checking above should guarantee that there are no SQL errors below
    sqls = pg_rollup.Rollup(
        table_name,
        is_temp,
        tablespace_name,
        rollup_name,
        process_list(wheres_list, 'key'),
        process_list(rollups_list, 'algebra', parse_algebra=True),
        key
    ).create()
    for s in sqls:
        plpy.execute(s)

    # insert into the pg_rollup table
    if key:
        event_id_sequence_name = f"'{table_name}_{key}_seq'"
        rollup_column = key
    else:
        # FIXME: set rollup_column to primary key
        event_id_sequence_name = 'NULL'
        rollup_column = None
    plpy.execute(f"insert into pg_rollup (rollup_name, table_name, rollup_column, event_id_sequence_name, sql, mode) values ('{rollup_name}','{table_name}','{rollup_column}',{event_id_sequence_name},'{rollup_name}_raw_manualrollup','init')")

    # set the rollup mode
    plpy.execute("select rollup_mode('"+rollup_name+"','"+mode+"')")

    # insert values into the rollup
    plpy.execute(f"select {rollup_name}_raw_reset();")
$$
LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION rollup_mode(rollup_name REGCLASS, mode TEXT)
RETURNS VOID AS $func$
    
    sql = (f"select * from pg_rollup where rollup_name='{rollup_name}'")
    pg_rollup = plpy.execute(sql)[0]

    ########################################    
    # turn off the old mode
    # NOTE:
    # we should maintain the invariant that whenever we disable the old mode,
    # the rollup tables are consistent with the underlying table;
    # this requires calling the do_rollup function for all non-trigger options,
    # which is potentially an expensive operation.
    ########################################    
    if pg_rollup['mode'] == 'trigger':
        plpy.execute(f"""
            DROP TRIGGER IF EXISTS {rollup_name}_insert ON {pg_rollup['table_name']};
            DROP TRIGGER IF EXISTS {rollup_name}_update ON {pg_rollup['table_name']};
            DROP TRIGGER IF EXISTS {rollup_name}_delete ON {pg_rollup['table_name']};
            UPDATE pg_rollup SET last_aggregated_id=COALESCE((select max({pg_rollup['rollup_column']}) from {pg_rollup['table_name']}),0) WHERE rollup_name='{rollup_name}';
            """)

    if pg_rollup['mode'] == 'cron':
        plpy.execute(f'''
            SELECT cron.unschedule('pg_rollup.{rollup_name}');
            ''')
        plpy.execute(f"select do_rollup('{rollup_name}');")

    if pg_rollup['mode'] == 'manual':
        plpy.execute(f"select do_rollup('{rollup_name}');")

    ########################################    
    # enter the new mode
    ########################################    
    if mode=='cron':
        # we use a "random" delay on the cron job to ensure that all of the jobs
        # do not happen at the same time, overloading the database
        sql = (f"select count(*) as count from cron.job where jobname ilike 'pg_rollup.%';")
        num_jobs = plpy.execute(sql)[0]['count']
        delay = 13*num_jobs%60
        plpy.execute(f'''
            SELECT cron.schedule(
                'pg_rollup.{rollup_name}',
                '* * * * *',
                $$SELECT do_rollup('{rollup_name}',delay_seconds=>{delay});$$
            );
            ''')

    if mode=='trigger':

        # first we do a manual rollup to ensure that the rollup table is up to date
        if pg_rollup['event_id_sequence_name'] is not None:
            plpy.execute(f"select do_rollup('{rollup_name}');")

        # next we create triggers
        rollup_table_name = rollup_name+'_raw'
        sql = ('''
            CREATE TRIGGER '''+rollup_name+'''_insert
                AFTER INSERT
                ON ''' + pg_rollup['table_name'] + '''
                REFERENCING NEW TABLE AS new_table
                FOR EACH STATEMENT
                EXECUTE PROCEDURE ''' + rollup_table_name+'''_triggerfunc();

            CREATE TRIGGER '''+rollup_name+'''_update
                AFTER UPDATE
                ON ''' + pg_rollup['table_name'] + '''
                REFERENCING NEW TABLE AS new_table
                            OLD TABLE AS old_table
                FOR EACH STATEMENT
                EXECUTE PROCEDURE ''' + rollup_table_name+'''_triggerfunc();

            CREATE TRIGGER '''+rollup_name+'''_delete
                AFTER DELETE
                ON ''' + pg_rollup['table_name'] + '''
                REFERENCING OLD TABLE AS old_table
                FOR EACH STATEMENT
                EXECUTE PROCEDURE ''' + rollup_table_name+'''_triggerfunc();
                ''')
        plpy.execute(sql)

    plpy.execute(f"UPDATE pg_rollup SET mode='{mode}' WHERE rollup_name='{rollup_name}';")
$func$
LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION drop_rollup(rollup_name REGCLASS)
RETURNS VOID AS $$
    import pg_rollup
    sql = pg_rollup.drop_rollup_str(rollup_name)
    plpy.execute(sql)
$$
LANGUAGE plpython3u
RETURNS NULL ON NULL INPUT;

