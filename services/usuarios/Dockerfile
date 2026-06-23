FROM node:20-alpine AS deps
WORKDIR /app
COPY services/usuarios/package*.json ./
RUN npm install --omit=dev --no-audit --no-fund

FROM node:20-alpine
RUN apk add --no-cache curl
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY services/usuarios/ .
USER 1000
EXPOSE 3000
CMD ["node", "server.js"]
