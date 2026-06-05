FROM python:3.12-slim
WORKDIR /app

RUN groupadd -g 1000 appuser && useradd -u 1000 -g appuser -m appuser

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

RUN mkdir -p /app/data && chown -R appuser:appuser /app

EXPOSE 8000

ENTRYPOINT ["./entrypoint.sh"]