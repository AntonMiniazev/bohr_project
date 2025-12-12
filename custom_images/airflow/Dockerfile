FROM apache/airflow:3.1.4-python3.13

# install provider and dependencies
RUN pip install --no-cache-dir \
    apache-airflow-providers-microsoft-mssql[common.sql] \
    apache-airflow-providers-amazon[apache.hive] \
    pyodbc~=5.2.0

USER airflow
# Use custom requirements
COPY requirements.txt /requirements.txt

# Install additional dependencies
RUN pip install --no-cache-dir -r /requirements.txt

ENV PYTHONPATH="/opt/airflow/dags/repo/dags"