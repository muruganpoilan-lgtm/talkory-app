FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install --omit=dev
COPY . .
ENV NODE_ENV=production
EXPOSE 3000
RUN mkdir -p /data/kyc /data/avatars/public /data/avatars/pending /data/app && chown -R node:node /data/kyc /data/avatars /data/app
USER node
CMD ["node", "src/server.js"]
