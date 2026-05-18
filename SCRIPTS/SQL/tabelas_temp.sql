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

CREATE TABLE temp_estacoes (
    cd_estacao          VARCHAR2(20),
    dc_nome             VARCHAR2(100),
    sg_estado           VARCHAR2(5),
    tp_estacao          VARCHAR2(30),
    cd_situacao         VARCHAR2(30),
    vl_latitude         NUMBER(12,8),
    vl_longitude        NUMBER(12,8),
    vl_altitude         NUMBER(8,2),
    dt_inicio_operacao  DATE,
    dt_fim_operacao     DATE,
    fl_capital          VARCHAR2(2)
);