sh bench/run_transact_tbls.sh 10 trigger
sh bench/run_transact_tbls.sh 100 trigger 
sh bench/run_transact_tbls.sh 500 trigger
#sh bench/run_transact_tbls.sh 10000 trigger
sh bench/run_transact_cols.sh 10 trigger
sh bench/run_transact_cols.sh 100 trigger
sh bench/run_transact_cols.sh 500 trigger
sh bench/run_transact_tbls.sh 10 manual
sh bench/run_transact_tbls.sh 100 manual 
sh bench/run_transact_tbls.sh 500 manual
sh bench/run_transact_cols.sh 10 manual
sh bench/run_transact_cols.sh 100 manual
sh bench/run_transact_cols.sh 500 manual

cat bench/tbl_data.csv
cat bench/col_data.csv
cat bench/manual_tbl_data.csv
cat bench/manual_col_data.csv
