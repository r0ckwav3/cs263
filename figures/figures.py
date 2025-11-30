import csv as csv_module
from io import StringIO

import matplotlib.pyplot as plt

csv = """
test,strong,weak,unowned,unsafe
create,134.962,181.800,138.643,134.682
deref,101.107,105.399,100.520,101.422
destroy,173.022,242.510,175.566,171.259
destroy minus create,38.060,60.710,36.923,36.577
"""

# Parse CSV string
reader = csv_module.reader(StringIO(csv.strip()))
rows = list(reader)
header = rows[0][1:]  # skip first and last empty columns
data = rows[1:]

# For each row, plot a bar chart
for row in data:
    label = row[0]
    values = [float(x) for x in row[1:]]  # skip first and last empty columns
    cmap = plt.get_cmap("cool")
    colors = [cmap(i / (len(values) - 1)) for i in range(len(values))]
    plt.figure(figsize=(4, 4))
    plt.bar(header, values, color=colors, width=0.4)  # Make bars thinner by reducing width
    plt.title(label)
    plt.ylabel("Value")
    plt.xlabel("Reference Type")
    plt.tight_layout()
    # Save the figure instead of showing it
    filename = f"{label.replace(' ', '_')}.png"
    plt.savefig(filename)
    plt.close()
