FROM node:22.23.2-bookworm-slim AS node
FROM python:3.14.7-slim-bookworm
COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/npm
RUN ln -s /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
WORKDIR /tools
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY *.py *.cjs *.json ./
CMD ["python", "kfgqpc.py", "--help"]
