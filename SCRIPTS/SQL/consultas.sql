-- CONSULTAS ANALÍTICAS

-- 1. AGREGAÇÃO SIMPLES
-- Total de casos de TB por ano no Paraná
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


-- 2. AGREGAÇÃO SIMPLES
-- Top 10 municípios com mais casos acumulados (2018-2023)
SELECT
    m.nm_municipio,
    m.nm_regiao,
    SUM(f.casos_tb) AS total_casos
FROM fato_tuberculose f
JOIN dim_municipio m ON m.sk_municipio = f.sk_municipio
GROUP BY m.nm_municipio, m.nm_regiao
ORDER BY total_casos DESC
FETCH FIRST 10 ROWS ONLY;


-- 3. CASE / TRATAMENTO DE NULOS
-- Classificação de municípios por risco e situação de dados
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


-- 4. FUNCAO DE JANELA - LAG
-- Evolucao anual de casos com variacao em relacao ao ano anterior
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


-- 5. FUNCAO DE JANELA - RANK e NTILE
-- Ranking de municipios por total de casos com quartis
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


-- 6. FUNCAO DE JANELA - Media movel 
-- Tendencia de casos por municipio (janela de 3 anos)
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


-- 7. OLAP - ROLLUP
-- Casos por regiao e ano com subtotais automaticos
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


-- 8. OLAP - CUBE
-- pandemia x faixa de PIB
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


-- 9. OLAP - GROUPING SETS
-- Subtotais especificos: por ano e por regiao separadamente
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


-- 10. VIEW SIMPLES
-- Indicadores consolidados por municipio e ano
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


-- 11. VIEW MATERIALIZADA
-- Resumo por regiao e ano (pre-calculado para relatorios)
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


-- 12. SQL/XML
-- Exportar os 10 municipios com mais casos em XML
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


-- 13. SQL/JSON
-- Resumo anual do estado em formato JSON
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


-- 14. CONSULTA NA VIEW SIMPLES
-- Municipios de uma regiao com casos acima da media regional
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


-- 15. CONSULTA NA VIEW MATERIALIZADA
-- Regioes: casos durante a pandemia vs fora dela
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