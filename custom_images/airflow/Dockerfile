FROM apache/airflow:3.1.5-python3.12

ARG AIRFLOW_VERSION=3.1.5
ARG PYTHON_VERSION=3.12
ARG CONSTRAINT_URL="https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

# install providers with Airflow constraints to avoid incompatible deps
RUN pip install --no-cache-dir \
    apache-airflow-providers-microsoft-mssql[common.sql] \
    apache-airflow-providers-amazon[apache.hive] \
    apache-airflow-providers-fab[common.compat] \
    --constraint "${CONSTRAINT_URL}"


USER airflow
# Use custom requirements
COPY requirements.txt /requirements.txt

# Install additional dependencies
RUN pip install --no-cache-dir -r /requirements.txt

ENV PYTHONPATH="/opt/airflow/dags/repo/dags"
