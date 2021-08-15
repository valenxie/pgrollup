docker-compose up -d
rm bench/tbl_data.csv
rm bench/col_data.csv
rm bench/manual_tbl_data.csv
rm bench/manual_col_data.csv
docker-compose exec db bash -c "sh bench/shell_commands.sh"
#python3 draw.py
