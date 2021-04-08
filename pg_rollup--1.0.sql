\echo Use "CREATE EXTENSION pg_rollup" to load this file. \quit

--------------------------------------------------------------------------------

CREATE TABLE algebra (
    id                      SERIAL PRIMARY KEY,
    name                    TEXT NOT NULL,
    agg                     TEXT NOT NULL,
    type                    TEXT NOT NULL,
    zero                    TEXT NOT NULL,
    plus                    TEXT NOT NULL,
    negate                  TEXT,
    view                    TEXT
);

CREATE TABLE viewop (
    id                      SERIAL PRIMARY KEY,
    id_algebra              INTEGER REFERENCES algebra(id),
    op                      TEXT NOT NULL,
    value                   TEXT NOT NULL
);

/*
 * postgres-native algebra
 *
 * FIXME: the following aggregate functions could be implemented, but are not
 * bit_and
 * bit_or
 */

INSERT INTO algebra
    (name           ,agg                            ,type       ,zero                       ,plus                           ,negate ,view)
    VALUES
    ('count'        ,'count(x)'                     ,'INTEGER'  ,'0'                        ,'count(x)+count(y)'            ,'-x'   ,'x'),
    ('sum'          ,'sum(x)'                       ,'x'        ,'0'                        ,'sum(x)+sum(y)'                ,'-x'   ,'x'),
    ('min'          ,'min(x)'                       ,'x'        ,'null'                     ,'least(min(x),min(y))'         ,NULL   ,'x'),
    ('max'          ,'max(x)'                       ,'x'        ,'null'                     ,'greatest(max(x),max(y))'      ,NULL   ,'x'),
    ('bool_and'     ,'bool_and(x)'                  ,'BOOL'     ,'TRUE'                     ,'bool_and(x) and bool_and(y)'  ,NULL   ,'x'),
    ('bool_or'      ,'bool_or(x)'                   ,'BOOL'     ,'FALSE'                    ,'bool_or(x) or bool_or(y)'     ,NULL   ,'x');

INSERT INTO algebra
    (name,agg,type,zero,plus,negate,view)
    VALUES
    ( 'avg'
    , 'avg(x)'
    , 'FLOAT'
    , 'null'
    , 'avg(x)*(count(x)/(count(x)+count(y))::FLOAT)+avg(y)*(count(y)/(count(x)+count(y))::FLOAT)'
    , 'x'
    , 'x'
    ),
    ( 'var_pop'
    , 'var_pop(x)'
    , 'FLOAT'
    , 'null'
    , '(count(x)/(count(x)+count(y)::FLOAT))*(var_pop(x)+(avg(x) - count(x)/(count(x)+count(y)::FLOAT)*avg(x) - count(y)/(count(x)+count(y)::FLOAT)*avg(y))^2) + (count(y)/(count(x)+count(y)::FLOAT))*(var_pop(y)+(avg(y) - count(y)/(count(x)+count(y)::FLOAT)*avg(y) - count(x)/(count(x)+count(y)::FLOAT)*avg(x))^2)'
    , 'x'
    , 'x'
    ),
    ( 'var_samp'
    , 'var_samp(x)'
    , 'FLOAT'
    , 'null'
    , 'null'
    , 'x'
    , 'CASE WHEN count(x) > 1 THEN var_pop(x)*count(x)/(count(x)-1) ELSE var_pop(x) END'
    ),
    ( 'variance'
    , 'variance(x)'
    , 'FLOAT'
    , 'null'
    , 'null'
    , 'x'
    , 'CASE WHEN count(x) > 1 THEN var_pop(x)*count(x)/(count(x)-1) ELSE var_pop(x) END'
    ),
    ( 'stddev'
    , 'stddev(x)'
    , 'FLOAT'
    , 'null'
    , 'null'
    , 'x'
    , 'CASE WHEN count(x) > 1 THEN sqrt(var_pop(x)*count(x)/(count(x)-1)) ELSE stddev(x) END'
    ),
    ( 'stddev_samp'
    , 'stddev_samp(x)'
    , 'FLOAT'
    , 'null'
    , 'null'
    , 'x'
    , 'CASE WHEN count(x) > 1 THEN sqrt(var_pop(x)*count(x)/(count(x)-1)) ELSE stddev_samp(x) END'
    ),
    ( 'stddev_pop'
    , 'stddev_pop(x)'
    , 'FLOAT'
    , 'null'
    , 'null'
    , 'x'
    , 'CASE WHEN count(x) > 1 THEN sqrt(var_pop(x)) ELSE stddev_pop(x) END'
    );

--------------------------------------------------------------------------------

/* 
 * Algebras defined in external libraries goes here.
 * For each library, we first check if the extension is installed.
 * Then, we only define the library specific code if the extension actually is installed.
 * This ensures that the pg_rollup library can work even when these optional dependencies are not met.
 *
 * NOTE:
 * The following libraries have not been included as dependencies for this project,
 * but they might be included in the future.
 *
 * Apache MADLib: https://madlib.apache.org/docs/master/group__grp__sketches.html
 * Provides sketch datastructures, but they have no union, and I'm not sure how to install it
 *
 * https://github.com/ozturkosu/cms_topn
 * doesn't build on postgres:12,10; appears abandoned
 */

/*
 * https://github.com/citusdata/postgresql-topn
 */
do $do$
DECLARE
    has_extension BOOLEAN;
BEGIN
SELECT true FROM pg_extension INTO has_extension WHERE extname='topn';
IF has_extension THEN

INSERT INTO algebra
    (name,agg,type,zero,plus,negate,view)
    VALUES
    ('topn'
    ,'topn_add_agg(x)'
    ,'JSONB'
    ,$$'{}'$$
    ,'topn_union(topn(x),topn(y))'
    ,NULL
    --,'topn(topn(x),1)'
    ,'topn(x)'
    );

END IF;
END
$do$ language 'plpgsql';

/*
 * https://github.com/citusdata/postgresql-hll
 */
do $do$
DECLARE
    has_extension BOOLEAN;
BEGIN
SELECT true FROM pg_extension INTO has_extension WHERE extname='hll';
IF has_extension THEN

INSERT INTO algebra
    (name,agg,type,zero,plus,negate,view)
    VALUES
    ('hll'
    ,'hll_add_agg(hll_hash_any(x))'
    ,'hll'
    ,'hll_empty()'
    ,'hll(x)||hll(y)'
    ,NULL
    ,'round(hll_cardinality(hll(x)))'
    );

END IF;
END
$do$ language 'plpgsql';

/*
 * https://pgxn.org/dist/datasketches/
 */

do $do$
DECLARE
    has_extension BOOLEAN;
BEGIN
SELECT true FROM pg_extension INTO has_extension WHERE extname='datasketches';
IF has_extension THEN

CREATE OR REPLACE FUNCTION kll_float_sketch_union(a kll_float_sketch, b kll_float_sketch) RETURNS kll_float_sketch AS $$
    select kll_float_sketch_merge(sketch) from (select a as sketch union all select b) t;
$$ LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

CREATE OR REPLACE FUNCTION frequent_strings_sketch_union(a frequent_strings_sketch, b frequent_strings_sketch) RETURNS frequent_strings_sketch AS $$
    select frequent_strings_sketch_merge(9,sketch) from (select a as sketch union all select b) t;
$$ LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

INSERT INTO algebra
    (name,agg,type,zero,plus,negate,view)
    VALUES
    ('kll_float_sketch'
    ,'kll_float_sketch_build(x)'
    ,'kll_float_sketch'
    ,'null'
    ,'kll_float_sketch_union(kll_float_sketch(x),kll_float_sketch(y))'
    ,NULL
    ,'kll_float_sketch_get_quantile(kll_float_sketch(x),0.5)'
    ),
    ('frequent_strings_sketch'
    ,'frequent_strings_sketch_build(9,x)'
    ,'frequent_strings_sketch'
    ,'null'
    ,'frequent_strings_sketch_union(frequent_strings_sketch(x),frequent_strings_sketch(y))'
    ,NULL
    ,'frequent_strings_sketch_result_no_false_negatives(frequent_strings_sketch(x))'
    --,$$'to view, apply frequent_strings_sketch_result_no_false_negatives(x) to the _raw rollup table'$$
    );

    /*
    -- FIXME: plus doesn't throw an error, but gives really bad results, possibly due to an uncaught error
    -- FIXME: the datasketches library implements an intersection function, but no negate function;
    ('theta_sketch'
    ,'theta_sketch_build(x)'
    ,'theta_sketch','theta_sketch_build(null::int)'
    ,'theta_sketch_union(theta_sketch(x),theta_sketch(y))'
    ,NULL
    ,'round(theta_sketch_get_estimate(x))'
    ),
 
    -- FIXME: plus throws an error, this is due to a problem in the datasketches library and not something that can be fixed locally
    ('hll_sketch'
    ,'hll_sketch_union(hll_sketch_build(x))'
    ,'hll_sketch'
    ,'hll_sketch_build(null::int)'
    ,'hll_sketch_union(x,y)'
    ,NULL
    ,'round(hll_sketch_get_estimate(x))'
    ),

    -- FIXME: plus throws an error, this is due to a problem in the datasketches library and not something that can be fixed locally
    ('cpc_sketch'
    ,'cpc_sketch_union(cpc_sketch_build(x))'
    ,'cpc_sketch','cpc_sketch_build(null::int)'
    ,'cpc_sketch_union(x,y)'
    ,NULL
    ,'round(cpc_sketch_get_estimate(x))'
    );
    */

END IF;
END
$do$ language 'plpgsql';

/*
 * https://github.com/tvondra/tdigest
 */  
do $do$
DECLARE
    has_extension BOOLEAN;
BEGIN
SELECT true FROM pg_extension INTO has_extension WHERE extname='tdigest';
IF has_extension THEN

CREATE OR REPLACE FUNCTION tdigest_union(a tdigest, b tdigest) RETURNS tdigest AS $$
    select tdigest(sketch) from (select a as sketch union all select b) t;
$$ LANGUAGE 'sql' IMMUTABLE PARALLEL SAFE;

INSERT INTO algebra
    (name,agg,type,zero,plus,negate,view)
    VALUES
    ('tdigest'
    ,'tdigest(x,100)'
    ,'tdigest'
    ,'null' --,'tdigest(null,100)'
    ,'tdigest_union(tdigest(x),tdigest(y))'
    ,NULL
    ,'tdigest_percentile(tdigest(x),0.5)'
    );

END IF;
END
$do$ language 'plpgsql';

--------------------------------------------------------------------------------

CREATE TABLE pgrollup_rollups (
    rollup_name TEXT NOT NULL,
    table_alias TEXT NOT NULL,
    table_name TEXT NOT NULL,
    event_id_sequence_name TEXT,
    rollup_column TEXT,
    sql TEXT NOT NULL,
    mode TEXT NOT NULL,
    last_aggregated_id BIGINT DEFAULT 0,
    PRIMARY KEY (rollup_name,table_alias)
);

CREATE TABLE pg_rollup_settings (
    name TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
INSERT INTO pg_rollup_settings (name,value) VALUES
    ('default_mode','trigger');

/*
 * Whenever the source table for a rollup is dropped,
 * the rollup should be deleted as well.
 * This trigger ensures the rollup gets dropped.
 *
 * FIXME:
 * This trigger doesn't seem to fire when a temporary table is automatically dropped at the end of a session.
 */
CREATE OR REPLACE FUNCTION pg_rollup_drop_function()
RETURNS event_trigger AS $$
DECLARE
    obj record;
    rollup record;
BEGIN
    IF tg_tag LIKE 'DROP%'
    THEN
        FOR obj IN SELECT * FROM pg_event_trigger_dropped_objects()
        LOOP
            FOR rollup IN SELECT * FROM pgrollup_rollups WHERE table_name=obj.object_name
            LOOP
                PERFORM drop_rollup(rollup.rollup_name);
            END LOOP;
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
    table_alias text,
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
    -- FIXME:
    -- the COALESCEs here are assuming that the sequence is positive;
    -- that's the default value, but these can be changed;
    -- the *REALLY* correct thing to do here is to extract the minimum value from the sequence and use that
    --SELECT table_name, COALESCE(last_aggregated_id+1,0), LEAST(COALESCE(last_aggregated_id,0)+max_rollup_size+1,COALESCE(pg_sequence_last_value(event_id_sequence_name),0))
    SELECT table_name, last_aggregated_id+1, LEAST(last_aggregated_id+max_rollup_size+1,pg_sequence_last_value(event_id_sequence_name))
    INTO table_to_lock, window_start, window_end
    FROM pgrollup_rollups
    WHERE pgrollup_rollups.rollup_name = incremental_rollup_window.rollup_name 
      AND pgrollup_rollups.table_alias = incremental_rollup_window.table_alias 
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE 'rollup ''%'' is not in pgrollup_rollups', rollup_name;
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
    UPDATE pgrollup_rollups SET last_aggregated_id = window_end
    WHERE pgrollup_rollups.rollup_name = incremental_rollup_window.rollup_name
      AND pgrollup_rollups.table_alias = incremental_rollup_window.table_alias;
END;
$function$;


CREATE FUNCTION do_rollup(
    rollup_name text default null,
    table_alias text default null,
    max_rollup_size bigint default 4611686018427387904, -- 2**62
    force_safe boolean default true,
    delay_seconds integer default 0
)
RETURNS TABLE (
    _rollup_name TEXT,
    _table_alias TEXT,
    start_id BIGINT,
    end_id BIGINT
)
LANGUAGE plpgsql
AS $function$
DECLARE
    sql_command text;
    obj record;
    ret record;
    mode text;
    start_id bigint;
    end_id bigint;
BEGIN
    -- if no rollup_name is provided,
    -- then we'll do a rollup on all of the tables
    IF rollup_name IS NULL THEN
        FOR obj IN SELECT * FROM pgrollup_rollups WHERE event_id_sequence_name IS NOT NULL
        LOOP
            RETURN QUERY SELECT * FROM do_rollup(
                obj.rollup_name,
                obj.table_alias,
                do_rollup.max_rollup_size,
                do_rollup.force_safe,
                do_rollup.delay_seconds
                );
        END LOOP;
        RETURN;
    END IF;

    -- if no table_alias is provided,
    -- then we'll do a rollup on all of the table_aliases
    IF table_alias IS NULL THEN
        FOR obj IN SELECT * FROM pgrollup_rollups WHERE pgrollup_rollups.rollup_name=do_rollup.rollup_name
        LOOP
            RETURN QUERY SELECT * FROM do_rollup(
                do_rollup.rollup_name,
                obj.table_alias,
                do_rollup.max_rollup_size,
                do_rollup.force_safe,
                do_rollup.delay_seconds
                );
        END LOOP;
        RETURN;
    END IF;

    /* sleeping is how cron ensures that the jobs are staggered in time */
    PERFORM pg_sleep(delay_seconds);

    /* determine which page views we can safely aggregate */
    SELECT window_start, window_end INTO start_id, end_id
    FROM incremental_rollup_window(rollup_name,table_alias,max_rollup_size,force_safe);

    /* exit early if there are no new page views to aggregate */
    IF start_id > end_id OR start_id IS NULL OR end_id IS NULL THEN 
        RETURN QUERY SELECT rollup_name,table_alias,start_id,end_id;
        RETURN;
    END IF;

    /* this is the new code that gets the rollup command from the table
     * and executes it */
    SELECT pgrollup_rollups.sql 
    INTO sql_command
    FROM pgrollup_rollups 
    WHERE pgrollup_rollups.rollup_name = do_rollup.rollup_name;

    EXECUTE 'select '||sql_command||'($1,$2)' USING start_id,end_id;

    -- return
    RETURN QUERY SELECT rollup_name,table_alias,start_id,end_id;
END;
$function$;


CREATE OR REPLACE FUNCTION pgrollup(
    text TEXT,
    dry_run BOOLEAN DEFAULT FALSE,
    mode TEXT DEFAULT NULL
)
RETURNS VOID AS $$
    import pg_rollup.parsing
    cmds = pg_rollup.parsing.parse_create(text)
    for cmd in cmds:
        sql = f'''
        SELECT create_rollup_internal(
            $1,
            columns => $2,
            joininfos => $3,
            groups => $4,
            where_clause => $5,
            having_clause => $6,
            dry_run => $7,
            mode => $8
        ) as result;'''
        plan = plpy.prepare(sql,[
            'text',
            'text[]',
            'json',
            'text[]',
            'text',
            'text',
            'boolean',
            'text',
            ])
        result = plpy.execute(plan,[
            cmd['rollup_name'],
            cmd['columns'],
            cmd['joininfos'],
            cmd['groups'],
            cmd['where_clause'],
            cmd['having_clause'],
            dry_run,
            mode,
            ])

$$
LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION create_rollup_internal(
    rollup_name TEXT,
    columns TEXT[],
    joininfos JSON DEFAULT '[]',
    groups TEXT[] DEFAULT NULL,
    where_clause TEXT DEFAULT NULL,
    having_clause TEXT DEFAULT NULL,
    tablespace TEXT DEFAULT NULL,
    mode TEXT DEFAULT NULL,
    dry_run BOOLEAN DEFAULT FALSE
    )
RETURNS TEXT AS $$
    import pg_rollup
    import pg_rollup.parsing_functions
    import re
    import collections
    import json

    global joininfos
    joininfos = json.loads(joininfos)

    def get_type(expr):
        '''
        helper funcions that returns the type of expr
        '''
        sql = (f'''
            select {expr}
            '''
            +
            ''.join([
            '''
            ''' + joininfo['join_type'] + ' ' + joininfo['table_name'] + ' AS ' + joininfo['table_alias'] + ' ' + joininfo['condition']
            for joininfo in joininfos
            ])
            +
            '''
            limit 1;
            ''')
        res = plpy.execute(sql)
        t_oid = res.coltypes()[0]
        sql = f'select typname,typlen from pg_type where oid={t_oid} limit 1;'
        row = plpy.execute(sql)[0]
        return row


    # get a list of all algebras
    sql = f'select * from algebra;'
    rows = plpy.execute(sql)
    all_algebras = list(rows)

    # if no mode provided, calculate the default mode
    global mode
    if mode is None:
        mode = plpy.execute("select value from pg_rollup_settings where name='default_mode';")[0]['value'];
        if mode is None:
            mode = 'trigger'

    # if no tablespace provided, calculate the default tablespace
    global tablespace
    if tablespace is None:
        # FIXME: the default tablespace is not guaranteed to be "pg_default"
        tablespace_name = 'pg_default'
    else:
        tablespace_name = tablespace

    # extract a list of wheres and rollups from the input parameters
    global groups
    if groups is None:
        groups=[]

    groups_list = []
    for value,name in groups:
        groups_list.append(pg_rollup.Key(value,get_type(value),name,None))

    # columns_view_list contains the columns that will be included in the created view
    columns_view_list = []
    raw_columns = []
    for value,name in columns:
        value_substitute_views = pg_rollup.parsing_functions.substitute_views(value, all_algebras)
        deps, value_view = pg_rollup.parsing_functions.extract_algebras(value_substitute_views, all_algebras)
        columns_view_list.append(pg_rollup.ViewKey(value_view,name))
        for dep in deps:
            raw_columns.append(dep)

    # columns_raw_list contains the columns that will be included in the raw table
    columns_raw_list = []
    raw_columns = sorted(list(set(raw_columns)))
    for value in raw_columns:
        # extract key info
        name = '"'+value+'"'
        algebra = value[:value.find("(")]
        expr = value[value.find("(")+1:value.rfind(")")]
        type = get_type(expr)

        # get the algebra dictionary and key
        sql = f"select * from algebra where name='{algebra}';"
        res = list(plpy.execute(sql))
        if len(res)==1:
            algebra_dictionary = res[0]
            key = pg_rollup.Key(expr,type,name,algebra_dictionary)
        else:
            plpy.error(f'algbera {algebra} not found in the algebra table')

        # add column info
        columns_raw_list.append(key)

        # add dependencies to raw_columns if they are not present
        def extract_functions(text):
            functions = []
            for match in re.finditer(r'\b([a-zA-Z0-9_]+)\([xy]\)', text):
                functions.append(match.group(1))
            return functions

        deps = extract_functions(algebra_dictionary['plus'])
        if algebra_dictionary['plus'].strip().lower() == 'null':
            deps += extract_functions(algebra_dictionary['view'])

        for dep in deps:
            matched = False
            if f'{dep}({expr})' not in raw_columns:
                raw_columns.append(f'{dep}({expr})')

    # if there are any duplicate names in columns_raw_list, throw an error;
    # this should never happen, and is simply a consistency check
    names = [k.name for k in columns_raw_list]
    duplicate_names = [item for item, count in collections.Counter(names).items() if count > 1]
    if len(duplicate_names) > 0:
        plpy.warning('names='+str(names))
        plpy.error(f'duplicate names in columns: '+str(duplicate_names))

    # check if the table is temporary
    is_temp = False
    for joininfo in joininfos:
        sql = f"SELECT relpersistence='t' as is_temp FROM pg_class where relname='{joininfo['table_name']}'"
        is_temp = is_temp or plpy.execute(sql)[0]['is_temp']

    # compute the information needed for manual/cron rollups
    for joininfo in joininfos:
        rollup_column = joininfo.get('rollup_column')
        table_name = joininfo['table_name']
        if rollup_column:
            event_id_sequence_name = f"{table_name}_{rollup_column}_seq"
        else:
            # no rollup_column was given, so we try to use the primary key
            sql=f'''
            SELECT ind_column.attname AS pk
            FROM pg_class tbl
            JOIN pg_index ind ON ind.indrelid = tbl.oid
            JOIN pg_class ind_table ON ind_table.oid = ind.indexrelid
            JOIN pg_attribute ind_column ON ind_column.attrelid = ind_table.oid
            WHERE tbl.relname = '{table_name}'
              AND ind.indisprimary;
            '''
            pks = list(plpy.execute(sql))

            event_id_sequence_name = None
            rollup_column = None
            if len(pks) == 0:
                plpy.notice(f'no primary key in table {table_name}')
            elif len(pks) > 1:
                plpy.notice(f'multi-column primary key in table {table_name}')
            else:
                event_id_sequence_name = f"{table_name}_{pks[0]['pk']}_seq"
                rollup_column = pks[0]['pk']
        joininfo['rollup_column'] = rollup_column
        joininfo['event_id_sequence_name'] = event_id_sequence_name

        # verify that the computed sequence exists in the db
        sql = f"SELECT relname FROM pg_class WHERE relkind = 'S' and relname='{event_id_sequence_name}';";
        matches = list(plpy.execute(sql))
        if len(matches) == 0:
            plpy.notice(f'sequence "{event_id_sequence_name}" not found in table')
            event_id_sequence_name = None
            rollup_column = None

        # display warning messages
        if joininfo.get('rollup_column') is None:
            plpy.notice(f'event_id_sequence_name={event_id_sequence_name}')
            plpy.notice('no valid sequence found for manual/cron rollups; the only available rollup type is trigger')

    # verify that there are no subqueries
    if where_clause and re.search(r'\(\s*select', where_clause, re.IGNORECASE):
        plpy.error('subqueries not allowed in the WHERE clause')
    if having_clause and re.search(r'\(\s*select', having_clause, re.IGNORECASE):
        plpy.error('subqueries not allowed in the HAVING clause')

    # constuct the sql statements for generating the rollup, and execute them
    # the error checking above should guarantee that there are no SQL errors below
    sqls = pg_rollup.Rollup(
        joininfos,
        is_temp,
        tablespace_name,
        rollup_name,
        groups_list,
        columns_raw_list,
        columns_view_list,
        where_clause,
        having_clause,
    ).create()

    # set the rollup mode
    sqls += f"""
    select rollup_mode('{rollup_name}','{mode}');
    """

    # insert values into the rollup
    sqls += f"""
    select {rollup_name}_raw_reset();
    """

    if not dry_run:
        plpy.execute(sqls)
    else:
        plpy.notice('the given command would execute the following SQL code:\n\n'+sqls)
$$
LANGUAGE plpython3u;

CREATE OR REPLACE FUNCTION create_rollup(
    table_name  REGCLASS,
    rollup_name TEXT,
    tablespace TEXT DEFAULT NULL,
    wheres TEXT DEFAULT '',
    rollups TEXT DEFAULT 'count(*) AS count',
    key TEXT DEFAULT NULL,
    mode TEXT DEFAULT NULL
    )
RETURNS VOID AS $$
    import pg_rollup
    import json

    global table_name

    wheres_list = pg_rollup._extract_arguments(wheres)
    if len(wheres_list)==1 and wheres_list[0].strip()=='':
        wheres_list=[]

    groups_list = []
    for group in wheres_list:
        group = group.strip()
        if 'AS' in group:
            value,name = group.split('AS')
            value = value.strip()
            name = name.strip()
        elif 'as' in group:
            value,name = group.split('as')
            value = value.strip()
            name = name.strip()
        else:
            value = group
            name = group.replace('(','_').replace(')','_').replace('*','_')
        groups_list.append([value,name])

    rollups_list = pg_rollup._extract_arguments(rollups)
    if len(rollups_list)==1 and rollups_list[0].strip()=='':
        rollups_list=[]

    columns_list = []
    for column in rollups_list:
        column = column.strip()
        if 'AS' in column:
            value,name = column.split('AS')
            value = value.strip()
            name = name.strip()
        elif 'as' in column:
            value,name = column.split('as')
            value = value.strip()
            name = name.strip()
        else:
            value = column
            name = '"' + value + '"'
        columns_list.append([value,name])

    sql = f'''SELECT create_rollup_internal(
        $1,
        joininfos => $2,
        columns => $3,
        groups => $4,
        tablespace => $5,
        mode => $6
    );'''
    plan = plpy.prepare(sql,[
        'text',
        'JSON',
        'text[]',
        'text[]',
        'text',
        'text'
        ])
    plpy.execute(plan, [
        rollup_name,
        json.dumps([{
            'table_name':table_name,
            'table_alias':table_name,
            'condition':'',
            'join_type':'FROM',
            'rollup_column':key,
            }]),
        columns_list,
        groups_list,
        tablespace,
        mode
        ])
$$ language plpython3u;


CREATE OR REPLACE FUNCTION rollup_mode(
    rollup_name REGCLASS,
    mode TEXT
)
RETURNS VOID AS $func$
    
    sql = (f"select * from pgrollup_rollups where rollup_name='{rollup_name}'")
    rows = list(plpy.execute(sql))

    for pg_rollup in rows:
        if mode != 'trigger' and pg_rollup['event_id_sequence_name'] is None:
            plpy.error(f'''"mode" must be 'trigger' when "event_id_sequence_name" is NULL''')

        ########################################    
        # turn off the old mode
        # NOTE:
        # we should maintain the invariant that whenever we disable the old mode,
        # the rollup tables are consistent with the underlying table;
        # this requires calling the do_rollup function for all non-trigger options,
        # which is potentially an expensive operation.
        ########################################    
        if pg_rollup['mode'] == 'trigger':
            plpy.execute(f'''
                SELECT pgrollup_unsafedroptriggers__{rollup_name}__{pg_rollup['table_alias']}();
                ''')

        if pg_rollup['mode'] == 'cron':
            plpy.execute(f'''
                SELECT cron.unschedule('pg_rollup.{rollup_name}');
                ''')
            plpy.execute(f"""
                select do_rollup('{rollup_name}','{pg_rollup['table_alias']}');
                """)

        if pg_rollup['mode'] == 'manual':
            plpy.execute(f"""
                select do_rollup('{rollup_name}','{pg_rollup['table_alias']}');
                """)

        ########################################    
        # enter the new mode
        ########################################    
        if mode=='cron':
            # we use a "random" delay on the cron job to ensure that all of the jobs
            # do not happen at the same time, overloading the database
            sql = (f"""
                SELECT count(*) AS count
                FROM cron.job
                WHERE jobname ILIKE 'pg_rollup.%';
                """)
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
                plpy.execute(f"""
                    select do_rollup('{rollup_name}','{pg_rollup['table_alias']}');
                    """)

            # next we create triggers
            sql = 'select pgrollup_unsafecreatetriggers__'+rollup_name+'__'+pg_rollup['table_alias']+'();'
            plpy.execute(sql)

    plpy.execute(f"UPDATE pgrollup_rollups SET mode='{mode}' WHERE rollup_name='{rollup_name}';")
$func$
LANGUAGE plpython3u;


CREATE OR REPLACE FUNCTION drop_rollup(rollup_name REGCLASS)
RETURNS VOID AS $$
    import pg_rollup
    #sql = pg_rollup.drop_rollup_str(rollup_name)
    sql = 'select pgrollup_drop__'+rollup_name+'();'
    plpy.execute(sql)
$$
LANGUAGE plpython3u
RETURNS NULL ON NULL INPUT;



------------------------------------------------------------------------------------------------------------------------
-- the following functions are used to verify the correctness of rollup tables;
-- they are primarily intended for use in the test cases;
-- these functions are potentially slow, and so production use should be careful;
--
-- the function assert_rollup checks for exact equality between the rollup and the groundtruth;
-- it should be used on rollups with only discrete entries that are deterministically generated
--
-- the function assert_rollup_relative_error checks for approximate equality between the rollup and the groundtruth;
-- it should be used on rollups that either use floating point calculations or have internal randomness;
-- the relative_error parameter must be tuned to the accuracy guarantee provided by the rollup algebra

CREATE OR REPLACE FUNCTION assert_rollup(rollup_name REGCLASS)
RETURNS VOID AS $$
    sql = f'select * from {rollup_name}_groundtruth except select * from {rollup_name};';
    res1 = plpy.execute(sql)
    sql = f'select * from {rollup_name} except select * from {rollup_name}_groundtruth;';
    res2 = plpy.execute(sql)

    for row in res1:
        plpy.warning(f'result only in {rollup_name}_groundtruth: {str(row)}')
    for row in res2:
        plpy.warning(f'result only in {rollup_name}: {str(row)}')

    assert len(res1)==0
    assert len(res2)==0
$$ LANGUAGE plpython3u STRICT IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION relative_error(a double precision, b double precision) RETURNS DOUBLE PRECISION AS $$
    select greatest(abs(a),abs(b))/least(abs(a),abs(b))-1;
$$ LANGUAGE 'sql' STRICT IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION rollup_column_relative_error(rollup_name REGCLASS, column_name TEXT) RETURNS DOUBLE PRECISION AS $$
    sql = f'select "{column_name}" from {rollup_name};';
    res = plpy.execute(sql)
    assert len(res)==1
    val1 = res[0][column_name]

    sql = f'select "{column_name}" from {rollup_name}_groundtruth;';
    res = plpy.execute(sql)
    assert len(res)==1
    val2 = res[0][column_name]

    sql = f'select relative_error({val1},{val2}) as relative_error;';
    res = plpy.execute(sql)
    return res[0]['relative_error']
$$ LANGUAGE plpython3u STRICT IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION assert_rollup_column_relative_error(rollup_name REGCLASS, column_name TEXT, relative_error DOUBLE PRECISION) RETURNS VOID AS $$
    sql = f"select rollup_column_relative_error('{rollup_name}','{column_name}') as relative_error;";
    res = plpy.execute(sql)
    if not res[0]['relative_error'] < relative_error:
        plpy.error(f"relative_error={res[0]['relative_error']} > {relative_error}")
$$ LANGUAGE plpython3u STRICT IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION assert_rollup_relative_error(rollup_name REGCLASS, relative_error DOUBLE PRECISION) RETURNS VOID AS $$
    sql = f"select * from {rollup_name} where true limit 1;"
    res = plpy.execute(sql)
    columns = res[0].keys()
    plpy.error('columns={str(columns)}')

    sql = f"select rollup_column_relative_error('{rollup_name}','{column_name}') as relative_error;";
    res = plpy.execute(sql)
    if not res[0]['relative_error'] < relative_error:
        plpy.error(f"relative_error={res[0]['relative_error']} > {relative_error}")
$$ LANGUAGE plpython3u STRICT IMMUTABLE PARALLEL SAFE;


CREATE OR REPLACE FUNCTION assert_rollup_relative_error(rollup_name REGCLASS, relative_error DOUBLE PRECISION) RETURNS VOID AS $$
    # get a list of the columns in the rollup
    sql = f"select * from {rollup_name} where true limit 1;"
    res = plpy.execute(sql)
    columns = res[0].keys()

    # count the number of columns that do not satisfy the relative_error condition
    num_bad_columns = 0
    for column_name in columns:
        sql = f"select rollup_column_relative_error('{rollup_name}','{column_name}') as relative_error;";
        res = plpy.execute(sql)
        if not res[0]['relative_error'] < relative_error:
            plpy.warning(f"column {column_name} has relative_error={res[0]['relative_error']} > {relative_error}")
            num_bad_columns+=1

    # the test case
    assert num_bad_columns==0

$$ LANGUAGE plpython3u STRICT IMMUTABLE PARALLEL SAFE;
