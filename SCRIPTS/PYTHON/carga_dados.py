import oracledb
import pandas as pd
import numpy as np
import json

def limpar_nulos(lista_de_listas):
    resultado = []
    for linha in lista_de_listas:
        nova_linha = []
        for val in linha:
            if val is None:
                nova_linha.append(None)
            elif isinstance(val, float) and np.isnan(val):
                nova_linha.append(None)
            else:
                try:
                    if pd.isna(val):
                        nova_linha.append(None)
                    else:
                        nova_linha.append(val)
                except (TypeError, ValueError):
                    nova_linha.append(val)
        resultado.append(nova_linha)
    return resultado

try:
    conexao = oracledb.connect(
        user="SYSTEM",
        password="1234",
        dsn="localhost:1522/XEPDB1"
    )
    cursor = conexao.cursor()
    print("Conexão com Oracle estabelecida com sucesso!")
except Exception as e:
    print(f"Erro ao conectar: {e}")
    exit()


# carregando CSV (dataSUS, clima_pr_2018_2023, densidade_demografica)

print("Carregando dataSUS")
df_sus = pd.read_csv('../../dados/brutos/dataSUS.csv', sep=';', encoding='utf-8', dtype=str)

df_sus.columns = [
    'municipio_raw', 'casos_2018', 'casos_2019', 'casos_2020',
    'casos_2021', 'casos_2022', 'casos_2023', 'total'
]
df_sus = df_sus[df_sus['municipio_raw'] != 'Total'].copy()

dados_sus = limpar_nulos(df_sus.values.tolist())

sql_sus = """
    INSERT INTO temp_dataSUS (
        municipio_raw, casos_2018, casos_2019, casos_2020, 
        casos_2021, casos_2022, casos_2023, total
    ) VALUES (:1, :2, :3, :4, :5, :6, :7, :8)
"""

# insere em lote
cursor.executemany(sql_sus, dados_sus)
print(f"{cursor.rowcount} linhas inseridas em temp_dataSUS")
# ---------------------------------------------------------------------------------

print("Carregando clima_pr_2018_2023")
df_clima = pd.read_csv('../../dados/processados/clima_pr_2018_2023.csv', sep=',')

df_clima['data'] = pd.to_datetime(df_clima['data'], format='mixed')

df_clima = df_clima[[
    'ano', 'codigo_estacao', 'nome_estacao', 'latitude', 'longitude',
    'altitude', 'data', 'temp_max_c', 'temp_min_c',
    'temp_med_c', 'umidade_med_pct', 'precipitacao_mm'
]]

dados_clima = limpar_nulos(df_clima.values.tolist())

sql_clima = """
    INSERT INTO temp_clima (
        ano, codigo_estacao, nome_estacao, latitude, longitude,
        altitude, data_medicao, temp_max_c, temp_min_c,
        temp_med_c, umidade_med_pct, precipitacao_mm
    ) VALUES (:1, :2, :3, :4, :5, :6, :7, :8, :9, :10, :11, :12)
"""
cursor.executemany(sql_clima, dados_clima)
print(f"{cursor.rowcount} linhas inseridas em temp_clima")
# ---------------------------------------------------------------------------------

print("Carregando densidade_demografica")
df_densidade = pd.read_csv('../../dados/processados/densidade_demografica.csv', sep=';', encoding='utf-8')

df_densidade.columns = [
    'municipio', 'regiao',
    'dens_2018', 'dens_2019', 'dens_2020',
    'dens_2021', 'dens_2022', 'dens_2023'
]

dados_densidade = limpar_nulos(df_densidade.values.tolist())

sql_dens = """
    INSERT INTO temp_densidade (
        municipio, regiao, dens_2018, dens_2019, 
        dens_2020, dens_2021, dens_2022, dens_2023
    ) VALUES (:1, :2, :3, :4, :5, :6, :7, :8)
"""
cursor.executemany(sql_dens, dados_densidade)
print(f"{cursor.rowcount} linhas inseridas em temp_densidade")

# carregando JSON

print("Carregando JSON tempo")
caminho_json = '../../dados/brutos/apiTempo.json'

with open(caminho_json, 'r', encoding='utf-8') as f:
    conteudo_json = f.read()

cursor.execute(
    "INSERT INTO temp_estacoes_json (conteudo) VALUES (:1)",
    [conteudo_json])
print("JSON inserido em temp_estacoes_json")


# carregando XML
print("Carregando XML do PIB")
caminho_xml = '../../dados/processados/pib_municipal.xml'

with open(caminho_xml, 'r', encoding='utf-8') as f:
    conteudo_xml = f.read()

cursor.setinputsizes(oracledb.DB_TYPE_CLOB)

cursor.execute(
    "INSERT INTO temp_pib_xml (conteudo) VALUES (XMLType(:1))",
    [conteudo_xml])
print("XML inserido em temp_pib_xml")


conexao.commit()
cursor.close()
conexao.close()