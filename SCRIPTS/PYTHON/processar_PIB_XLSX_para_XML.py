import pandas as pd

df = pd.read_excel("pib_municipial_2017-2023.xlsx", header=None, skiprows=3)

df.columns = [
    "municipio",
    "per_capita_2017", "per_capita_2018", "per_capita_2019",
    "per_capita_2020", "per_capita_2021", "per_capita_2022", "per_capita_2023",
    "pib_total_2017", "pib_total_2018", "pib_total_2019",
    "pib_total_2020", "pib_total_2021", "pib_total_2022", "pib_total_2023"
]

df = df[df["municipio"].notna()]
df = df[~df["municipio"].astype(str).str.contains("PRODUTO INTERNO", na=False)]
df = df[df["municipio"] != "MUNICÍPIOS"]

df = df[df["pib_total_2018"].notna()]

# apenas 2018-2023
df = df.drop(columns=["per_capita_2017", "pib_total_2017"])

df = df.reset_index(drop=True)

xml_lines = ['<?xml version="1.0" encoding="UTF-8"?>']
xml_lines.append('<pib_municipios>')

for _, row in df.iterrows():
    xml_lines.append('  <municipio>')
    for col in df.columns:
        tag = col.replace(' ', '_')
        valor = '' if pd.isna(row[col]) else str(row[col])
        if valor.endswith('.0'):
            valor = valor[:-2]
        xml_lines.append(f'    <{tag}>{valor}</{tag}>')
    xml_lines.append('  </municipio>')

xml_lines.append('</pib_municipios>')

with open("pib_municipal.xml", "w", encoding="utf-8") as f:
    f.write('\n'.join(xml_lines))

print(f"XML gerado com {len(df)} municipos")