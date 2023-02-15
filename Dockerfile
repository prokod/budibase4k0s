FROM node:alpine

WORKDIR /root

RUN apk --no-cache add nfs-utils openrc bash curl && rc-update add nfsmount

RUN yarn global add @budibase/cli@2.3.10

CMD exec /bin/bash -c "trap : TERM INT; sleep infinity & wait"

