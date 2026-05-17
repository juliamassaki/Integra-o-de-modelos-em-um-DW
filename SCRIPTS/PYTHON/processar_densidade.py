import pandas as pd

df = pd.read_csv("Densidade Demográfica_Tabela.csv", 
                 encoding="utf-16", 
                 sep="\t",
                 skiprows=1,
                 decimal=",",
                 thousands=".")

df.columns = ["municipio", "regiao", 
              "dens_2018", "dens_2019", "dens_2020",
              "dens_2021", "dens_2022", "dens_2023"]

df = df[df["municipio"] != "Estado do Paraná"]
df = df[df["municipio"] != "Município/Estado"]

df = df.reset_index(drop=True)

df.to_csv("densidade_demografica.csv", sep=";", index=False, encoding="utf-8")

print(f"CSV gerado com {len(df)} municípios com sucesso!")