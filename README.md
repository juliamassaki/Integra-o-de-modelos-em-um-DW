# TB-Paraná-DW

> **Um Data Warehouse para análise multidimensional dos casos de Tuberculose no Paraná, cruzando dados de saúde, clima e indicadores socioeconómicos entre 2018 e 2023.**

## 1. Os Arquivos Brutos (Origem dos Dados)

Os dados que alimentam este projeto vieram de 3 fontes principais, com formatos variados (CSV, JSON, Excel):

* **DataSUS:** Dados de casos de Tuberculose por município (`dataSUS.csv`).
* **IBGE:** Dados de População/Densidade (`Densidade Demográfica_Tabela.csv`) e Financeiros (`pib_municipial_2017-2023.xlsx`).
* **INMET:** Dados de estações meteorológicas (`apiTempo.json`) e medições climáticas.

> ⚠️ **Nota sobre o INMET:** Os dados climáticos diários brutos (separados por ano e estação) estavam originalmente contidos numa pasta chamada `past_inmet`. Por ser uma pasta muito volumosa. No entanto, o seu resultado processado está incluído no projeto.

---

## 2. Processamento e Transformações (Python)

Antes de os dados entrarem no banco de dados, utilizámos scripts em Python (na pasta `SCRIPTS/PYTHON/`) para padronizar e formatar os dados brutos:

1. **`processar_PIB_XLSX_para_XML.py`**: Lê a planilha complexa do Excel contendo os PIBs e converte a informação para o formato XML, facilitando a extração via `XMLTABLE` no banco de dados.
2. **`processar_densidade.py`**: Limpa os dados do IBGE, removendo caracteres especiais e ajustando o encoding.
3. **`processar_inmet_pr.py`**: Varre a pasta bruta do INMET (aquela que ficou de fora do Git), agrupa os dados de todas as estações do Paraná e gera um ficheiro único consolidado (`clima_pr_2018_2023.csv`).
4. **`carga_dados.py`**: Script responsável por conectar ao banco de dados e popular as tabelas temporárias com os dados já limpos.

---

## 3. Banco de Dados - Tabelas Temporárias

Os dados entram sem grandes restrições apenas para serem consumidos.

```sql
-- CRIAÇÃO DAS TABELAS TEMPORÁRIAS

CREATE TABLE temp_dataSUS (
    municipio_raw   VARCHAR2(100),
    casos_2018      VARCHAR2(10),
    casos_2019      VARCHAR2(10),
    casos_2020      VARCHAR2(10),
    casos_2021      VARCHAR2(10),
    casos_2022      VARCHAR2(10),
    casos_2023      VARCHAR2(10),
    total           VARCHAR2(10)
);

CREATE TABLE temp_densidade (
    municipio   VARCHAR2(100),
    regiao      VARCHAR2(200),
    dens_2018   NUMBER(10,2),
    dens_2019   NUMBER(10,2),
    dens_2020   NUMBER(10,2),
    dens_2021   NUMBER(10,2),
    dens_2022   NUMBER(10,2),
    dens_2023   NUMBER(10,2)
);

CREATE TABLE temp_clima (
    ano                 NUMBER(4),
    codigo_estacao      VARCHAR2(20),
    nome_estacao        VARCHAR2(100),
    latitude            NUMBER(12,8),
    longitude           NUMBER(12,8),
    altitude            NUMBER(8,2),
    data_medicao        DATE,
    temp_max_c          NUMBER(6,2),
    temp_min_c          NUMBER(6,2),
    temp_med_c          NUMBER(6,2),
    umidade_med_pct     NUMBER(6,2),
    precipitacao_mm     NUMBER(8,2)
);

CREATE TABLE temp_pib_xml (
    conteudo XMLTYPE
);

CREATE TABLE temp_estacoes_json (
    conteudo CLOB
    CONSTRAINT chk_json CHECK (conteudo IS JSON)
);

```

### 3.2. Carga dos Dados (Python)
O script `carga_dados.py` entra em ação. Ele utiliza as bibliotecas pandas e oracledb para ler processar e inserir no banco de dados.

Para garantir alta performance e não sobrecarregar a memória, os dados em lote (CSV) são inseridos utilizando o método executemany, enquanto os XML e JSON são inseridos diretamente em colunas do tipo CLOB e XMLTYPE.

---

## 4. O Esquema Estrela (Tabelas Definitivas)

Nesta etapa, construímos a infraestrutura dimensional.

<img width="2125" height="1833" alt="diagrama ER - tuberculose" src="https://github.com/user-attachments/assets/12b920ad-cb97-47ee-85ee-396fdb9392a5" />

### A Evolução da Tabela Fato (Resolução de Problema)

Durante a modelagem, a primeira versão da Tabela Fato foi desenhada da seguinte forma:

```sql
-- VERSÃO 1 (DESCONTINUADA)
CREATE TABLE fato_tuberculose (
    sk_fat number(10) PRIMARY KEY,
    sk_municipio INT NOT NULL,
    sk_tempo INT NOT NULL,
    sk_socioeconomico INT,
    sk_clima INT,
    casos_tb NUMBER(6),
    CONSTRAINT fk_fat_mun FOREIGN KEY(sk_municipio)REFERENCES dim_municipio(sk_municipio),
    CONSTRAINT fk_fat_tempo FOREIGN KEY(sk_tempo)REFERENCES dim_tempo(sk_tempo),
    CONSTRAINT fk_fat_socio FOREIGN KEY(sk_socioeconomico)REFERENCES dim_socioeconomico(sk_socioeconomico),
    CONSTRAINT fk_fat_clima FOREIGN KEY(sk_clima)REFERENCES dim_clima(sk_clima)
);

```

**O Problema:** identificámos que a associação clima/estação feita  via dim_clima não garantia a estação geográfica correta para cada município — adicionámos sk_estacao diretamente na fato para tornar esse vínculo explícito.

**A Solução:** Alterámos a estrutura para incluir a coluna `sk_estacao` como uma Chave Estrangeira (Foreign Key) explícita e obrigatória (`NOT NULL`). Abaixo encontra-se o DDL definitivo utilizado no projeto.

### ESQUEMA ESTRELA



```sql
-- 2. CRIAÇÃO DO ESQUEMA ESTRELA

-- DIM TEMPO
CREATE TABLE dim_tempo (
    sk_tempo INT PRIMARY KEY,
    ano NUMBER(4) NOT NULL,
    pandemia  CHAR(1)
);

-- DIM MUNICÍPIO
CREATE TABLE dim_municipio (
    sk_municipio INT PRIMARY KEY,
    cd_ibge VARCHAR2(10) NOT NULL,
    nm_municipio VARCHAR2(100) NOT NULL,
    nm_regiao VARCHAR2(200)
);

-- DIM ESTAÇÃO
CREATE TABLE dim_estacao (
    sk_estacao INT PRIMARY KEY,
    cd_estacao VARCHAR2(20),
    nm_estacao VARCHAR2(100),
    tp_estacao VARCHAR2(30),
    cd_situacao VARCHAR2(30),
    latitude NUMBER(12,8),
    longitude NUMBER(12,8),
    altitude NUMBER(8,2)
);

-- DIM CLIMA (agregado anual por estação)
CREATE TABLE dim_clima (
    sk_clima INT PRIMARY KEY,
    sk_estacao INT NOT NULL,
    sk_tempo INT NOT NULL,
    temp_max_anual NUMBER(6,2),
    temp_min_anual NUMBER(6,2),
    temp_med_anual NUMBER(6,2),
    umidade_med_anual NUMBER(6,2),
    precipitacao_total NUMBER(10,2),
    dias_chuva NUMBER(5),
    CONSTRAINT fk_clima_est FOREIGN KEY(sk_estacao) REFERENCES dim_estacao(sk_estacao),
    CONSTRAINT fk_clima_temp FOREIGN KEY(sk_tempo) REFERENCES dim_tempo(sk_tempo)
);

-- DIM SOCIOECONÔMICO
CREATE TABLE dim_socioeconomico (
    sk_socioeconomico INT PRIMARY KEY,
    sk_municipio INT NOT NULL,
    sk_tempo INT NOT NULL,
    pib_per_capita NUMBER(15,2),
    pib_total NUMBER(20),
    dens_demografica NUMBER(10,2),
    CONSTRAINT fk_socio_mun FOREIGN KEY(sk_municipio) REFERENCES dim_municipio(sk_municipio),
    CONSTRAINT fk_socio_temp FOREIGN KEY(sk_tempo) REFERENCES dim_tempo(sk_tempo)
);

-- FATO TUBERCULOSE (VERSÃO CORRIGIDA)
CREATE TABLE fato_tuberculose (
    sk_fat number(10) PRIMARY KEY,
    sk_municipio INT NOT NULL,
    sk_tempo INT NOT NULL,
    sk_estacao INT NOT NULL,  -- Nova chave adicionada para correção
    sk_socioeconomico INT,
    sk_clima INT,
    casos_tb NUMBER(6),
    CONSTRAINT fk_fat_mun FOREIGN KEY(sk_municipio) REFERENCES dim_municipio(sk_municipio),
    CONSTRAINT fk_fat_tempo FOREIGN KEY(sk_tempo) REFERENCES dim_tempo(sk_tempo),
    CONSTRAINT fk_fat_estacao FOREIGN KEY(sk_estacao) REFERENCES dim_estacao(sk_estacao),
    CONSTRAINT fk_fat_socio FOREIGN KEY(sk_socioeconomico) REFERENCES dim_socioeconomico(sk_socioeconomico),
    CONSTRAINT fk_fat_clima FOREIGN KEY(sk_clima) REFERENCES dim_clima(sk_clima)
);

-- SEQUENCE PARA GERAR ID DA FATO
CREATE SEQUENCE seq_fato_tb START WITH 1 INCREMENT BY 1;

```

---

## 5. Processo de Carga e Inserts

O último passo da pipeline foi aplicar a inteligência de negócios: unpivot das colunas de anos, extração de arquivos XML, agregação (AVG/SUM) de dados meteorológicos e cruzamento espacial.

```sql
-- 3. CARGA DE DADOS (Temporárias -> Definitivas)

-- CARGA: DIM TEMPO (Seed Data)
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (1, 2018, 'N');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (2, 2019, 'N');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (3, 2020, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (4, 2021, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (5, 2022, 'S');
INSERT INTO dim_tempo (sk_tempo, ano, pandemia) VALUES (6, 2023, 'N');
COMMIT;

-- CARGA: DIM MUNICÍPIO
INSERT INTO dim_municipio (sk_municipio, cd_ibge, nm_municipio, nm_regiao)
SELECT 
    ROWNUM AS sk_municipio, cd_ibge, nm_municipio, nm_regiao
FROM (
    SELECT
        TRIM(SUBSTR(t.municipio_raw, 1, 6)) AS cd_ibge,
        TRIM(SUBSTR(t.municipio_raw, 8))    AS nm_municipio,
        d.regiao                            AS nm_regiao
    FROM (SELECT DISTINCT municipio_raw FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw, '^\d{6}')) t
    LEFT JOIN temp_densidade d ON UPPER(TRANSLATE(TRIM(d.municipio), 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ', 'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC'))
                                = UPPER(TRIM(SUBSTR(t.municipio_raw, 8)))
);
COMMIT;

-- CARGA: DIM ESTAÇÃO (Parse de JSON)
INSERT INTO dim_estacao (sk_estacao, cd_estacao, nm_estacao, tp_estacao, cd_situacao, latitude, longitude, altitude)
SELECT 
    ROWNUM, cd_estacao, dc_nome, tp_estacao, cd_situacao,
    TO_NUMBER(vl_lat, '99999.99999999', 'NLS_NUMERIC_CHARACTERS=''.,'''),
    TO_NUMBER(vl_lon, '99999.99999999', 'NLS_NUMERIC_CHARACTERS=''.,'''),
    TO_NUMBER(vl_alt, '99999.99',       'NLS_NUMERIC_CHARACTERS=''.,''')
FROM temp_estacoes_json s,
     JSON_TABLE(s.conteudo, '$[*]'
         COLUMNS (
             cd_estacao VARCHAR2(20) PATH '$.CD_ESTACAO',
             dc_nome VARCHAR2(100) PATH '$.DC_NOME',
             sg_estado VARCHAR2(5) PATH '$.SG_ESTADO',
             tp_estacao VARCHAR2(30) PATH '$.TP_ESTACAO',
             cd_situacao VARCHAR2(30) PATH '$.CD_SITUACAO',
             vl_lat VARCHAR2(20) PATH '$.VL_LATITUDE',
             vl_lon VARCHAR2(20) PATH '$.VL_LONGITUDE',
             vl_alt VARCHAR2(20) PATH '$.VL_ALTITUDE'
         )
     ) j
WHERE j.sg_estado = 'PR';
COMMIT;

-- CARGA: DIM CLIMA (Agregação Anual)
INSERT INTO dim_clima (sk_clima, sk_estacao, sk_tempo, temp_max_anual, temp_min_anual, temp_med_anual, umidade_med_anual, precipitacao_total, dias_chuva)
SELECT 
    ROWNUM, e.sk_estacao, t.sk_tempo, MAX(c.temp_max_c), MIN(c.temp_min_c), ROUND(AVG(c.temp_med_c), 2),
    ROUND(AVG(c.umidade_med_pct), 2), ROUND(SUM(NVL(c.precipitacao_mm, 0)), 2), COUNT(CASE WHEN c.precipitacao_mm > 0 THEN 1 END)
FROM temp_clima c
JOIN dim_estacao e ON e.cd_estacao = c.codigo_estacao
JOIN dim_tempo t ON t.ano = c.ano
GROUP BY e.sk_estacao, t.sk_tempo;
COMMIT;

-- CARGA: DIM SOCIOECONÔMICO (XMLTABLE e CROSS JOIN)
INSERT INTO dim_socioeconomico (sk_socioeconomico, sk_municipio, sk_tempo, pib_per_capita, pib_total, dens_demografica)
SELECT 
    ROWNUM, sk_municipio, sk_tempo, pib_per_capita, pib_total, dens_demografica
FROM (
    SELECT m.sk_municipio, t.sk_tempo,
        CASE t.ano
            WHEN 2018 THEN TO_NUMBER(NULLIF(x.per_capita_2018,''), '9999999')
            WHEN 2019 THEN TO_NUMBER(NULLIF(x.per_capita_2019,''), '9999999')
            WHEN 2020 THEN TO_NUMBER(NULLIF(x.per_capita_2020,''), '9999999')
            WHEN 2021 THEN TO_NUMBER(NULLIF(x.per_capita_2021,''), '9999999')
            WHEN 2022 THEN TO_NUMBER(NULLIF(x.per_capita_2022,''), '9999999')
            WHEN 2023 THEN TO_NUMBER(NULLIF(x.per_capita_2023,''), '9999999')
        END AS pib_per_capita,
        CASE t.ano
            WHEN 2018 THEN TO_NUMBER(NULLIF(x.pib_total_2018,''), '9999999999999')
            WHEN 2019 THEN TO_NUMBER(NULLIF(x.pib_total_2019,''), '9999999999999')
            WHEN 2020 THEN TO_NUMBER(NULLIF(x.pib_total_2020,''), '9999999999999')
            WHEN 2021 THEN TO_NUMBER(NULLIF(x.pib_total_2021,''), '9999999999999')
            WHEN 2022 THEN TO_NUMBER(NULLIF(x.pib_total_2022,''), '9999999999999')
            WHEN 2023 THEN TO_NUMBER(NULLIF(x.pib_total_2023,''), '9999999999999')
        END AS pib_total,
        CASE t.ano
            WHEN 2018 THEN d.dens_2018 WHEN 2019 THEN d.dens_2019
            WHEN 2020 THEN d.dens_2020 WHEN 2021 THEN d.dens_2021
            WHEN 2022 THEN d.dens_2022 WHEN 2023 THEN d.dens_2023
        END AS dens_demografica
    FROM dim_municipio m
    CROSS JOIN dim_tempo t
    LEFT JOIN (
        SELECT x2.* FROM temp_pib_xml p, XMLTABLE('/pib_municipios/municipio' PASSING p.conteudo COLUMNS 
            municipio VARCHAR2(200) PATH 'municipio', per_capita_2018 VARCHAR2(20) PATH 'per_capita_2018',
            per_capita_2019 VARCHAR2(20) PATH 'per_capita_2019', per_capita_2020 VARCHAR2(20) PATH 'per_capita_2020',
            per_capita_2021 VARCHAR2(20) PATH 'per_capita_2021', per_capita_2022 VARCHAR2(20) PATH 'per_capita_2022',
            per_capita_2023 VARCHAR2(20) PATH 'per_capita_2023', pib_total_2018 VARCHAR2(20) PATH 'pib_total_2018',
            pib_total_2019 VARCHAR2(20) PATH 'pib_total_2019', pib_total_2020 VARCHAR2(20) PATH 'pib_total_2020',
            pib_total_2021 VARCHAR2(20) PATH 'pib_total_2021', pib_total_2022 VARCHAR2(20) PATH 'pib_total_2022',
            pib_total_2023 VARCHAR2(20) PATH 'pib_total_2023') x2 WHERE x2.municipio NOT IN ('Estado do Paraná', 'MUNICÍPIOS')
    ) x ON UPPER(TRANSLATE(x.municipio, 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ', 'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC')) = UPPER(m.nm_municipio)
    LEFT JOIN temp_densidade d ON UPPER(TRANSLATE(d.municipio, 'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ', 'AAAAAAEEEEIIIIOOOOOUUUUCAAAAAAEEEEIIIIOOOOOUUUUC')) = UPPER(m.nm_municipio)
);
COMMIT;

-- CARGA: FATO TUBERCULOSE (Com Unpivot e Sequence)
INSERT INTO fato_tuberculose (sk_fat, sk_municipio, sk_tempo, sk_estacao, sk_socioeconomico, sk_clima, casos_tb)
SELECT 
    seq_fato_tb.NEXTVAL AS sk_fat,
    base.sk_municipio,
    base.sk_tempo,
    base.sk_estacao,
    base.sk_socioeconomico,
    base.sk_clima,
    base.casos_tb
FROM (
    SELECT
        m.sk_municipio, t.sk_tempo, s.sk_socioeconomico, 
        (SELECT dc.sk_clima FROM dim_clima dc JOIN dim_estacao de ON de.sk_estacao = dc.sk_estacao WHERE dc.sk_tempo = t.sk_tempo ORDER BY ABS(de.latitude - (-24.5)) FETCH FIRST 1 ROW ONLY) AS sk_clima,
        (SELECT de.sk_estacao FROM dim_estacao de ORDER BY ABS(de.latitude - (-24.5)) FETCH FIRST 1 ROW ONLY) AS sk_estacao,
        CASE WHEN tb.casos_raw = '-' OR tb.casos_raw IS NULL THEN 0 ELSE TO_NUMBER(TRIM(tb.casos_raw)) END AS casos_tb
    FROM dim_municipio m
    JOIN dim_tempo t ON 1=1
    JOIN (
        SELECT municipio_raw, '2018' ano_str, casos_2018 casos_raw FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2019', casos_2019 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2020', casos_2020 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2021', casos_2021 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2022', casos_2022 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
        UNION ALL SELECT municipio_raw, '2023', casos_2023 FROM temp_dataSUS WHERE REGEXP_LIKE(municipio_raw,'^\d{6}')
    ) tb ON TRIM(SUBSTR(tb.municipio_raw, 1, 6)) = m.cd_ibge AND TO_NUMBER(tb.ano_str) = t.ano
    JOIN dim_socioeconomico s ON s.sk_municipio = m.sk_municipio AND s.sk_tempo = t.sk_tempo
) base;
```
## 6. Consultas Analíticas

Com a arquitetura desenhada e os dados integrados, o modelo estrela permite consultas rápidas (OLAP) e cruzamentos complexos utilizando funções avançadas de SQL. Abaixo estão as análises geradas (presentes no arquivo `consultas.sql`):

**1. Agregação Simples: Total de casos de TB por ano no Paraná**

```sql
SELECT
    t.ano,
    t.pandemia,
    SUM(f.casos_tb) AS total_casos,
    COUNT(DISTINCT f.sk_municipio) AS municipios_com_casos
FROM fato_tuberculose f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
WHERE f.casos_tb > 0
GROUP BY t.ano, t.pandemia
ORDER BY t.ano;

```

**2. Agregação Simples: Top 10 municípios com mais casos acumulados (2018-2023)**

```sql
SELECT
    m.nm_municipio,
    m.nm_regiao,
    SUM(f.casos_tb) AS total_casos
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
GROUP BY m.nm_municipio, m.nm_regiao
ORDER BY total_casos DESC
FETCH FIRST 10 ROWS ONLY;

```

**3. Expressões CASE: Classificação de municípios por risco e situação de dados**

```sql
SELECT
    m.nm_municipio,
    m.nm_regiao,
    SUM(f.casos_tb) AS total_casos,
    CASE
        WHEN SUM(f.casos_tb) = 0 THEN 'Sem casos'
        WHEN SUM(f.casos_tb) BETWEEN 1 AND 5 THEN 'Baixo (1-5)'
        WHEN SUM(f.casos_tb) BETWEEN 6 AND 20 THEN 'Moderado (6-20)'
        WHEN SUM(f.casos_tb) > 20 THEN 'Alto (>20)'
    END AS categoria_risco,
    CASE
        WHEN MAX(s.pib_per_capita) IS NULL THEN 'Sem dado'
        WHEN MAX(s.pib_per_capita) < 20000 THEN 'PIB baixo (<20k)'
        WHEN MAX(s.pib_per_capita) < 40000 THEN 'PIB medio (20-40k)'
        ELSE 'PIB alto (>40k)'
    END AS faixa_pib,
    NVL(TO_CHAR(ROUND(AVG(s.dens_demografica), 2)), 'N/D') AS dens_media
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
LEFT JOIN dim_socioeconomico s ON s.sk_socioeconomico = f.sk_socioeconomico
GROUP BY m.nm_municipio, m.nm_regiao
ORDER BY total_casos DESC;

```

**4. Funções de Janela (LAG): Evolução anual e variação em relação ao ano anterior**

```sql
SELECT
    t.ano,
    SUM(f.casos_tb) AS total_casos,
    LAG(SUM(f.casos_tb)) OVER (ORDER BY t.ano) AS casos_ano_anterior,
    SUM(f.casos_tb) - LAG(SUM(f.casos_tb)) OVER (ORDER BY t.ano) AS variacao_absoluta,
    ROUND(
        (SUM(f.casos_tb) - LAG(SUM(f.casos_tb)) OVER (ORDER BY t.ano))
        / NULLIF(LAG(SUM(f.casos_tb)) OVER (ORDER BY t.ano), 0) * 100
    , 2) AS variacao_pct
FROM fato_tuberculose f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
GROUP BY t.ano
ORDER BY t.ano;

```

**5. Funções de Janela (RANK e NTILE): Ranking de municípios por total de casos com quartis**

```sql
SELECT
    nm_municipio,
    nm_regiao,
    total_casos,
    RANK() OVER (ORDER BY total_casos DESC) AS ranking,
    NTILE(4) OVER (ORDER BY total_casos DESC) AS quartil,
    ROUND(total_casos / SUM(total_casos) OVER () * 100, 2) AS pct_do_total
FROM (
    SELECT
        m.nm_municipio,
        m.nm_regiao,
        SUM(f.casos_tb) AS total_casos
    FROM fato_tuberculose f
    JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
    GROUP BY m.nm_municipio, m.nm_regiao
)
ORDER BY ranking
FETCH FIRST 20 ROWS ONLY;

```

**6. Funções de Janela (Média Móvel): Tendência de casos por município (janela de 3 anos)**

```sql
SELECT
    nm_municipio,
    ano,
    casos_tb,
    ROUND(AVG(casos_tb) OVER (
        PARTITION BY sk_municipio
        ORDER BY ano
        ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING
    ), 2) AS media_movel_3anos,
    SUM(casos_tb) OVER (
        PARTITION BY sk_municipio
        ORDER BY ano
        ROWS UNBOUNDED PRECEDING
    ) AS acumulado
FROM (
    SELECT f.sk_municipio, m.nm_municipio, t.ano, f.casos_tb
    FROM fato_tuberculose f
    JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
    JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
)
WHERE nm_municipio IN (
    SELECT nm_municipio FROM (
        SELECT m.nm_municipio, SUM(f.casos_tb) total
        FROM fato_tuberculose f
        JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
        GROUP BY m.nm_municipio
        ORDER BY total DESC
    ) FETCH FIRST 5 ROWS ONLY
)
ORDER BY nm_municipio, ano;

```

**7. OLAP (ROLLUP): Casos por região e ano com subtotais automáticos**

```sql
SELECT
    NVL(m.nm_regiao, 'TOTAL GERAL') AS regiao,
    NVL(TO_CHAR(t.ano), 'TODOS OS ANOS') AS ano,
    SUM(f.casos_tb) AS total_casos,
    ROUND(AVG(f.casos_tb), 2) AS media_por_municipio,
    MAX(f.casos_tb) AS max_casos,
    GROUPING(m.nm_regiao) AS grp_regiao,
    GROUPING(t.ano) AS grp_ano
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
GROUP BY ROLLUP(m.nm_regiao, t.ano)
ORDER BY grp_regiao, grp_ano, m.nm_regiao NULLS LAST, t.ano NULLS LAST;

```

**8. OLAP (CUBE): Cruzamento de Pandemia vs Faixa de PIB**

```sql
SELECT
    NVL(periodo, 'TODOS') AS periodo_pandemia,
    NVL(faixa_pib, 'TODAS') AS faixa_pib,
    SUM(total_casos) AS total_casos,
    COUNT(DISTINCT sk_municipio) AS municipios
FROM (
    SELECT
        f.sk_municipio,
        f.casos_tb AS total_casos,
        CASE t.pandemia
            WHEN 'S' THEN 'Pandemia (2020-2022)'
            ELSE 'Pre/Pos-Pandemia'
        END AS periodo,
        CASE
            WHEN s.pib_per_capita IS NULL THEN 'Sem dado'
            WHEN s.pib_per_capita < 20000 THEN 'PIB baixo'
            WHEN s.pib_per_capita < 40000 THEN 'PIB medio'
            ELSE 'PIB alto'
        END AS faixa_pib
    FROM fato_tuberculose f
    JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
    LEFT JOIN dim_socioeconomico s ON s.sk_socioeconomico = f.sk_socioeconomico
)
GROUP BY CUBE(periodo, faixa_pib)
ORDER BY periodo NULLS LAST, faixa_pib NULLS LAST;

```

**9. OLAP (GROUPING SETS): Subtotais específicos por ano e por região separadamente**

```sql
SELECT
    NVL(TO_CHAR(t.ano), '---') AS ano,
    NVL(m.nm_regiao,    '---') AS regiao,
    SUM(f.casos_tb) AS total_casos,
    GROUPING(t.ano) AS grp_ano,
    GROUPING(m.nm_regiao) AS grp_regiao
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
GROUP BY GROUPING SETS (
    (t.ano),
    (m.nm_regiao)
)
ORDER BY grp_ano, grp_regiao, t.ano NULLS LAST, m.nm_regiao NULLS LAST;

```

**10. Criação de VIEW: Indicadores consolidados por município e ano**

```sql
CREATE OR REPLACE VIEW vw_municipio_tb AS
SELECT
    m.cd_ibge,
    m.nm_municipio,
    m.nm_regiao,
    t.ano,
    t.pandemia,
    f.casos_tb,
    s.pib_per_capita,
    s.pib_total,
    s.dens_demografica,
    c.temp_max_anual,
    c.temp_min_anual,
    c.temp_med_anual,
    c.umidade_med_anual,
    c.precipitacao_total,
    c.dias_chuva,
    e.nm_estacao AS estacao_referencia
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
LEFT JOIN dim_socioeconomico s ON s.sk_socioeconomico = f.sk_socioeconomico
LEFT JOIN dim_clima c ON c.sk_clima = f.sk_clima
LEFT JOIN dim_estacao e ON e.sk_estacao = c.sk_estacao;

```

**11. Criação de MATERIALIZED VIEW: Resumo pré-calculado por região e ano para relatórios**

```sql
CREATE MATERIALIZED VIEW mv_regiao_ano
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
SELECT
    NVL(m.nm_regiao, 'Nao informado') AS regiao,
    t.ano,
    t.pandemia,
    COUNT(DISTINCT m.sk_municipio) AS qtd_municipios,
    SUM(f.casos_tb) AS total_casos,
    ROUND(AVG(f.casos_tb), 2) AS media_casos,
    ROUND(AVG(s.pib_per_capita), 2) AS pib_medio,
    ROUND(AVG(s.dens_demografica), 2) AS dens_media,
    ROUND(AVG(c.temp_med_anual), 2) AS temp_media,
    ROUND(AVG(c.umidade_med_anual), 2) AS umidade_media,
    ROUND(AVG(c.precipitacao_total), 2) AS precipitacao_media
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
LEFT JOIN dim_socioeconomico s ON s.sk_socioeconomico = f.sk_socioeconomico
LEFT JOIN dim_clima c ON c.sk_clima = f.sk_clima
GROUP BY NVL(m.nm_regiao, 'Nao informado'), t.ano, t.pandemia;

```

**12. SQL / XML: Exportar os 10 municípios com mais casos em formato XML**

```sql
SELECT XMLELEMENT("relatorio_tb",
    XMLATTRIBUTES('Tuberculose Parana 2018-2023' AS "titulo"),
    XMLAGG(
        XMLELEMENT("municipio",
            XMLELEMENT("nome", nm_municipio),
            XMLELEMENT("regiao", NVL(nm_regiao, 'N/D')),
            XMLELEMENT("total_casos", total_casos),
            XMLELEMENT("pib_medio", NVL(TO_CHAR(pib_medio), 'N/D'))
        )
        ORDER BY total_casos DESC
    )
).getClobVal() AS xml_resultado
FROM (
    SELECT
        m.nm_municipio,
        m.nm_regiao,
        SUM(f.casos_tb) AS total_casos,
        ROUND(AVG(s.pib_per_capita), 0) AS pib_medio
    FROM fato_tuberculose f
    JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
    LEFT JOIN dim_socioeconomico s ON s.sk_socioeconomico = f.sk_socioeconomico
    GROUP BY m.nm_municipio, m.nm_regiao
    ORDER BY total_casos DESC
    FETCH FIRST 10 ROWS ONLY
);

```

**13. SQL / JSON: Exportar o resumo anual do estado em formato JSON**

```sql
SELECT JSON_OBJECT(
    'ano' VALUE t.ano,
    'pandemia' VALUE t.pandemia,
    'total_casos' VALUE SUM(f.casos_tb),
    'municipios_afetados' VALUE COUNT(CASE WHEN f.casos_tb > 0 THEN 1 END),
    'temp_media_pr' VALUE ROUND(AVG(c.temp_med_anual), 2),
    'umidade_media_pr' VALUE ROUND(AVG(c.umidade_med_anual), 2),
    'precipitacao_media' VALUE ROUND(AVG(c.precipitacao_total), 2)
    RETURNING CLOB
) AS resumo_json
FROM fato_tuberculose f
JOIN dim_tempo t ON t.sk_tempo = f.sk_tempo
LEFT JOIN dim_clima c ON c.sk_clima = f.sk_clima
GROUP BY t.ano, t.pandemia
ORDER BY t.ano;

```

**14. Consulta na VIEW: Municípios de uma região com casos acima da média regional**

```sql
SELECT
    nm_municipio,
    ano,
    casos_tb,
    ROUND(AVG(casos_tb) OVER (PARTITION BY nm_regiao, ano), 2) AS media_regiao,
    pib_per_capita,
    temp_med_anual
FROM vw_municipio_tb
WHERE nm_regiao = 'RGI de Londrina'
ORDER BY ano, casos_tb DESC;

```

**15. Consulta na VIEW MATERIALIZADA: Impacto pandémico por região**

```sql
SELECT
    regiao,
    SUM(CASE WHEN pandemia = 'S' THEN total_casos ELSE 0 END) AS casos_pandemia,
    SUM(CASE WHEN pandemia = 'N' THEN total_casos ELSE 0 END) AS casos_fora_pandemia,
    SUM(total_casos) AS total_geral,
    ROUND(
        SUM(CASE WHEN pandemia = 'S' THEN total_casos ELSE 0 END)
        / NULLIF(SUM(CASE WHEN pandemia = 'N' THEN total_casos ELSE 0 END), 0)
    , 2) AS razao_pandemia
FROM mv_regiao_ano
GROUP BY regiao
ORDER BY total_geral DESC;
```
