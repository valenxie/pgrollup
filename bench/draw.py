import matplotlib
#matplotlib.use('Agg')
import matplotlib.pyplot as plt 
import csv

x = []
y = []
y1 = []
y2 = []
y3 = []
fig, axs = plt.subplots(2, 2)

with open ('bench/tbl_data.csv','r') as csvfile:
    lines = csv.reader(csvfile, delimiter=',')
    for row in lines:
        x.append(row[0])
        y.append(row[1])

print(x)
print(y)

with open ('bench/col_data.csv','r') as csvfile:
    lines = csv.reader(csvfile, delimiter=',')
    for row in lines:
        y1.append(row[1])

#axis[0,1].plot(x, y, color = 'g', marker = 'o', label = 'TPS data')
#axis[0,1].xlabel('Amount of columns')
#axis[0,1].ylabel('TPS')
#axis[0,1].title('Transactions per second with incrementing columns in a rollup table')
#axis[0,1].grid()

with open ('bench/manual_tbl_data.csv','r') as csvfile:
    lines = csv.reader(csvfile, delimiter=',')
    for row in lines:
        y2.append(row[1])

with open ('bench/manual_col_data.csv','r') as csvfile:
    lines = csv.reader(csvfile, delimiter=',')
    for row in lines:
        y3.append(row[1])

axs[0, 0].plot(x, y)
axs[0, 0].set_title('Axis [0, 0]')
axs[0, 1].plot(x, y1, 'tab:orange')
axs[0, 1].set_title('Axis [0, 1]')
axs[1, 0].plot(x, y2, 'tab:green')
axs[1, 0].set_title('Axis [1, 0]')
axs[1, 1].plot(x, y3, 'tab:red')
axs[1, 1].set_title('Axis [1, 1]')

#plt.savefig('plot.png', dpi=300, bbox_inches='tight')
plt.show()
