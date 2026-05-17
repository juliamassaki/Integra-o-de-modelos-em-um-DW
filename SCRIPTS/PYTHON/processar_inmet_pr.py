import os
import csv
import argparse
import glob
from collections import defaultdict, Counter

ANOS = [2018, 2019, 2020, 2021, 2022, 2023]

COLUNAS_INTERESSE = {
    "data":         ["Data", "DATA (YYYY-MM-DD)", "DATA"],
    "hora":         ["Hora UTC", "HORA (UTC)", "HORA"],
    "temp_max":     ["TEMPERATURA MAXIMA NA HORA ANT. (AUT) (°C)",
                     "TEMPERATURA MÁXIMA NA HORA ANT. (AUT) (°C)",
                     "Temp. Máx. (°C)"],
    "temp_min":     ["TEMPERATURA MINIMA NA HORA ANT. (AUT) (°C)",
                     "TEMPERATURA MÍNIMA NA HORA ANT. (AUT) (°C)",
                     "Temp. Mín. (°C)"],
    "temp_med":     ["TEMPERATURA DO AR - BULBO SECO, HORARIA (°C)",
                     "Temp. (°C)"],
    "umidade_med":  ["UMIDADE RELATIVA DO AR, HORARIA (%)",
                     "Umidade (%)"],
    "precipitacao": ["PRECIPITACAO TOTAL, HORARIO (mm)",
                     "PRECIPITAÇÃO TOTAL, HORÁRIO (mm)",
                     "Precipitação (mm)"],
}


def ler_metadados(caminho):
    meta = {}
    with open(caminho, encoding="latin-1") as f:
        for i, linha in enumerate(f):
            if i >= 8:
                break
            linha = linha.strip()
            if ";" in linha:
                partes = linha.split(";")
                chave = partes[0].replace(":", "").strip().upper()
                valor = partes[1].strip() if len(partes) > 1 else ""
                meta[chave] = valor
    return meta


def encontrar_col(header, opcoes):
    norm = [c.strip().upper() for c in header]
    for op in opcoes:
        if op.strip().upper() in norm:
            return norm.index(op.strip().upper())
    return None


def safe_float(v):
    if v is None:
        return None
    s = str(v).strip().replace(",", ".")
    if s in ("", "-9999", "-9999.0", "null", "NULL", "-"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def processar_arquivo(caminho, ano):
    meta = ler_metadados(caminho)
    if meta.get("UF", "").strip().upper() != "PR":
        return []

    codigo = meta.get("CODIGO (WMO)", meta.get("CODIGO", "")).strip()
    nome = meta.get("ESTACAO", "").strip()
    lat = safe_float(meta.get("LATITUDE", ""))
    lon = safe_float(meta.get("LONGITUDE", ""))
    alt = safe_float(meta.get("ALTITUDE", ""))

    with open(caminho, encoding="latin-1") as f:
        linhas = f.readlines()

    header_idx = None
    for i, linha in enumerate(linhas):
        if i < 8:
            continue
        if "DATA" in linha.upper():
            header_idx = i
            break

    if header_idx is None:
        return []

    delim = ";" if ";" in linhas[header_idx] else ","
    reader = csv.reader(linhas[header_idx:], delimiter=delim)
    header_row = next(reader)

    idx = {k: encontrar_col(header_row, v) for k, v in COLUNAS_INTERESSE.items()}

    if idx["data"] is None:
        return []

    registros = []
    for row in reader:
        if not row or not row[0].strip():
            continue
        data_str = row[idx["data"]].strip() if idx["data"] < len(row) else ""
        if not data_str:
            continue

        hora_str = ""
        if idx["hora"] is not None and idx["hora"] < len(row):
            hora_str = row[idx["hora"]].strip().replace(" UTC", "")

        def gv(chave):
            i = idx.get(chave)
            return safe_float(row[i]) if (i is not None and i < len(row)) else None

        registros.append({
            "ano": ano, "codigo_estacao": codigo, "nome_estacao": nome,
            "latitude": lat, "longitude": lon, "altitude": alt,
            "data": data_str, "hora_utc": hora_str,
            "temp_max_c": gv("temp_max"), "temp_min_c": gv("temp_min"),
            "temp_med_c": gv("temp_med"), "umidade_pct": gv("umidade_med"),
            "precipitacao_mm": gv("precipitacao"),
        })
    return registros


def agregar_diario(registros):
    agrupado  = defaultdict(lambda: {k: [] for k in ["tmax","tmin","tmed","umid","prec"]})
    meta_est  = {}

    for r in registros:
        chave = (r["codigo_estacao"], r["data"])
        g = agrupado[chave]
        g["tmax"].append(r["temp_max_c"])
        g["tmin"].append(r["temp_min_c"])
        g["tmed"].append(r["temp_med_c"])
        g["umid"].append(r["umidade_pct"])
        g["prec"].append(r["precipitacao_mm"])
        if chave not in meta_est:
            meta_est[chave] = {k: r[k] for k in
                ["ano","nome_estacao","latitude","longitude","altitude"]}

    def med(lst):
        v = [x for x in lst if x is not None]
        return round(sum(v)/len(v), 2) if v else None
    def mx(lst):
        v = [x for x in lst if x is not None]; return max(v) if v else None
    def mn(lst):
        v = [x for x in lst if x is not None]; return min(v) if v else None
    def sm(lst):
        v = [x for x in lst if x is not None]; return round(sum(v),2) if v else None

    out = []
    for (cod, data), g in sorted(agrupado.items()):
        m = meta_est[(cod, data)]
        out.append({
            "ano": m["ano"], "codigo_estacao": cod,
            "nome_estacao": m["nome_estacao"],
            "latitude": m["latitude"], "longitude": m["longitude"],
            "altitude": m["altitude"], "data": data,
            "temp_max_c": mx(g["tmax"]), "temp_min_c": mn(g["tmin"]),
            "temp_med_c": med(g["tmed"]), "umidade_med_pct": med(g["umid"]),
            "precipitacao_mm": sm(g["prec"]),
        })
    return out


def main():
    parser = argparse.ArgumentParser(
        description="Consolida CSVs do INMET - Paraná 2018-2023")
    parser.add_argument("--pasta", required=True,
        help="Pasta raiz com subpastas 2018/, 2019/, ..., 2023/")
    parser.add_argument("--saida", default="clima_pr_2018_2023.csv",
        help="Arquivo CSV de saída")
    parser.add_argument("--granularidade", choices=["horario","diario"],
        default="diario", help="Granularidade dos dados (padrão: diario)")
    args = parser.parse_args()

    todos = []
    total_arq = 0
    arq_pr    = 0

    for ano in ANOS:
        pasta_ano = os.path.join(args.pasta, str(ano))
        if not os.path.isdir(pasta_ano):
            print(f"[AVISO] Pasta não encontrada: {pasta_ano}")
            continue

        arquivos = []
        for padrao in [f"{pasta_ano}/**/*.CSV", f"{pasta_ano}/**/*.csv",
                       f"{pasta_ano}/*.CSV",    f"{pasta_ano}/*.csv"]:
            arquivos.extend(glob.glob(padrao, recursive=True))
        arquivos = list(set(arquivos))

        print(f"\nAno {ano}: {len(arquivos)} arquivo(s)")
        for arq in sorted(arquivos):
            total_arq += 1
            nome_arq = os.path.basename(arq)
            # Filtro rápido pelo nome antes de abrir o arquivo
            if "_PR_" not in nome_arq.upper():
                continue
            print(f"  {nome_arq}")
            try:
                regs = processar_arquivo(arq, ano)
                if regs:
                    arq_pr += 1
                    todos.extend(regs)
                    print(f"    -> {len(regs)} registros horários")
                else:
                    print(f"    -> 0 registros (verifique UF no cabeçalho)")
            except Exception as e:
                print(f"    -> ERRO: {e}")

    print(f"\n{'='*55}")
    print(f"Arquivos encontrados  : {total_arq}")
    print(f"Arquivos PR lidos     : {arq_pr}")
    print(f"Registros horários    : {len(todos)}")

    if not todos:
        print("\n[ERRO] Nenhum dado. Verifique a estrutura de pastas.")
        return

    if args.granularidade == "diario":
        print("Agregando para granularidade diária...")
        dados = agregar_diario(todos)
        print(f"Registros diários     : {len(dados)}")
    else:
        dados = todos

    campos = list(dados[0].keys())
    with open(args.saida, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=campos)
        writer.writeheader()
        writer.writerows(dados)

    print(f"\nArquivo gerado: {args.saida}")
    print(f"Colunas: {', '.join(campos)}")

    estacoes = Counter(r["codigo_estacao"] for r in dados)
    print(f"\nEstações PR ({len(estacoes)}):")
    for cod, qtd in sorted(estacoes.items()):
        nome_est = next(r["nome_estacao"] for r in dados if r["codigo_estacao"] == cod)
        print(f"  {cod}  {nome_est:30s}  {qtd} dias")


if __name__ == "__main__":
    main()