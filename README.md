# Deploying low-code app-gen platform Budibase on k0s Kubernetes distribution

## Instlling k0s (1 controller + n workers)

### Prepare hardware

1. On all nodes where k0s is going to be installed
   1. Create new partition
   1. Mount it as /var/lib/k0s
1. Hostnames naming convention (Reason: easily traceable afterwards from k8s cluster) - `prefix-<role><n>-<ip>`
   1. role - worker/controller
   1. n - node id - optional
   1. ip - static ip dash separated

   ```sh
   # Example hostname for controller
   sudo hostnamectl set-hostname moriawalls-debian-controller1-192-168-68-3

   # Example hostname for worker
   sudo hostnamectl set-hostname theshire-ubuntu-worker1-192-168-68-4
   ```

1. ? To update /etc/hosts and match hostname for 127.0.1.1

### Download / Install k0s

```sh
sudo curl -sSLf https://get.k0s.sh | sudo sh
```

### Deploy k0s controller (w/ OpenEBS as k8s CSI)

```sh
sudo k0s install controller --enable-worker -c ./k0s.yaml
```

### Set OpenEBS hostpath storage class as default (optional)

```sh
kubectl patch storageclass openebs-hostpath -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Deploy k0s worker

1. Generate Token for worker

```sh
sudo k0s token create --role=worker
```

1. Add token to a file called `k0s-worker<n>-token-file` where n is the worker enumeration
1. Deploy worker on target node

```sh
sudo k0s install worker --token-file /home/na/k0s-worker01-token-file
```

### Create kubectl management host

1. install kubectl
   1. gpg sigining key, add repo, install

      ```sh
      sudo curl -fsSLo /etc/apt/keyrings/kubernetes-archive-keyring.gpg https://packages.cloud.google.com/apt/doc/apt-key.gpg
      echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
      sudo apt-get uppdate
      sudo apt-get install kubectl
      ```

1. Go to controller and there `cat /var/lib/k0s/pki/admin.conf`
1. Copy the content to management host under user's home dir under `.kube/config`
1. Modify cluster.server from `localhost:6443` to `<controller ip>:6443`

## Deploying Budibase

### Install Helm

```sh
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /etc/apt/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
sudo apt-get uppdate
sudo apt-get install kubectl
```

### Install Kustomize

```sh
curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"  | bash
```

### Install nginx-controller (for baremetal - NodePort style)

1. Preferred way is to deploy using helm

   ```sh
   helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
   helm repo update
   helm install ingress-nginx ingress-nginx/ingress-nginx --create-namespace --namespace ingress-nginx --set controller.service.type=NodePort   --set controller.service.nodePorts.http=32080 --set controller.service.nodePorts.https=32443
   ```

2. Option deploy using kubectl

   ```sh
   kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.5.1/deploy/static/provider/baremetal/deploy.yaml
   ```

   To delete nginx ingress after deploying with kubectl

   ```sh
   kubectl delete all  --all -n ingress-ngin
   ```

   > **Note:**
   >
   > Cleaning up floating around related resourcess after deploying nginx ingress using kubectl is tedious to say the least
   > This is why it is recommended to deploy nginx ingress using Helm which does much better job of cleaning up after removal

### Install nfs-common on all worker nodes

> **Note:**
> This is an important step! otherwise nfs based Persistent Volume will not funtion
>
> Indication that this package is missing on you workre node/s look for the following on a Deployment `describe` for a Deployment containing a pod requiring nfs mount:
>
> ```log
> Mounting command: mount
> Mounting arguments: -t nfs XXXXXXXXXXX /var/lib/k0s/kubelet/pods/669bd77e-3874-414e-b014-b7e95e0833cb/volumes/kubernetes.io~nfs/nfs-pv/...
> Output: mount: /var/lib/k0s/kubelet/pods/669bd77e-3874-414e-b014-b7e95e0833cb/volumes/kubernetes.io~nfs/nfs-pv: bad option; for several filesystems (e.g. nfs, cifs) you might need a /sbin/mount.<type> helper program.
> ```

### Install budibase (Helm chart v2.3.10)

```sh
helm repo add budibase https://budibase.github.io/budibase/
helm repo update
# budibase-k0s-values.yaml is Helm Values file that instruct Helm not to deploy ingress-nginx but use existing one
cd helm-post-render/kustomize
helm install --create-namespace -f ../../budibase-k0s-values.yaml --post-renderer ./kustomize --version 2.3.6 --namespace budibase budibase budibase/budibase
```

### Find node port to use to access budibasse

```sh
> kubectl get ingress -n budibase
NAME                CLASS    HOSTS   ADDRESS        PORTS   AGE
budibase-budibase   <none>   *       192.168.68.4   80      6h26m
```

```sh
> kubectl get services -n ingress-nginx
NAME                                 TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)                      AGE
ingress-nginx-controller             NodePort    10.100.84.85    <none>        80:30277/TCP,443:30020/TCP   6h38m
ingress-nginx-controller-admission   ClusterIP   10.99.217.233   <none>        443/TCP                      6h38m
```

## Helm Tips n' Tricks

1. To pull helm archive

   ```sh
   helm pull budibase/budibase --destination ./dev/git/helm/ --untar
   ```

1. Developing a Kustomize patch
   1. Pull source

      ```sh
      cd ~/dev/git/helm/budibase4k0s
      helm pull budibase/budibase --destination .
      ```

   1. To check the outcome of the patch

      ```sh
      # Comment all lines in kustomiztion.yaml but the all.yaml line
      helm template my-test ../budibase/ --post-renderer ./kustomize --debug --dry-run > out1.yaml
      # Un comment all lines in kustomiztion.yaml
      helm template my-test ../budibase/ --post-renderer ./kustomize --debug --dry-run > out2.yaml
      diff out1.yaml out2.yaml
      ```

   1. Show details on the chart installed (version etc.)

   ```sh
   helm show chart budibase/budibase
   ```

## kubectl cheatsheet

1. Find Pod by its IP (relies on jq utility being installed)

   ```sh
   kubectl get --all-namespaces  --output json  pods | jq '.items[] | select(.status.podIP=="10.244.1.49")' | jq .metadata.name
   ```

1. Restart deployment (i.e. nginx-controller)

   ```sh
   kubectl rollout restart deployment budibase-ingress-nginx-controller -n budibase
   ```

## Troubleshooting

1. [nginx--controller error port 80 is already in use. Please check the flag --http-port](https://kubernetes.github.io/ingress-nginx/troubleshooting/#unable-to-listen-on-port-80443) when using budibase's Helm chart supplied nginx ingress

   1. Interim solution I found was to update nginx controller from 1.1.0 to 1.1.3
      1. Patch deployment:

         ```sh
         kubectl set image deployment/budibase-ingress-nginx-controller controller=k8s.gcr.io/ingress-nginx/controller:v1.1.3@sha256:31f47c1e202b39fadecf822a9b76370bd4baed199a005b3e7d4d1455f4fd3fe2 --record
         ```

      1. If need be - force restart:

         ```sh
         kubectl patch deployment budibase-ingress-nginx-controller -p   "{\"spec\":{\"template\":{\"metadata\":{\"annotations\":{\"date\":\"`date +'%s'`\"}}}}}"
         ```

   1. In the end I dropped this solution in favor of cluster wide ingress-nginx installation using Helm

1. `Error: INSTALLATION FAILED: rendered manifests contain a resource that already exists. Unable to continue with install: IngressClass "nginx" in namespace "" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "[meta.helm.sh/release-name](https://meta.helm.sh/release-name)" ...`
   1. Look if IngressClasses are flowting around - if it does delete

      ```sh
      kubectl get Ingressclass --all-namespaces
      ```

   1. Look if nginx related ClusterRoleBindings are floating aroung - if it does delete

      ```sh
      kubectl get clusterrolebindings  | grep nginx
      ```

   1. Look if nginx related ClusterRoles are floating around - if it does delete

      ```sh
      kubectl get clusterroles  | grep nginx
      ```

   1. Look if there are any nginx related validatingwebhookconfigurations - if it does delete

      ```sh
      # Search
      kubectl get validatingwebhookconfigurations
      # Delete
      kubectl delete validatingwebhookconfigurations ingress-nginx-admission
      ```

1. `rejected since it cannot handle ["BIG_CREATION"]`
   1. This is evident in logs within couchdb pod
   1. The pod contains couchdb container and sidecar container with [clouseau](https://github.com/cloudant-labs/clouseau) which provides lucene search capabilities to couchdb 3.x
   1. The error is due to incompatible ErLang protocol between the two.
   1. Solution: To patch helm chart downgrading couchdb from v3.2.1 to v3.1.2

## Refrences

1. [Nodeport vs Hostport](https://www.reddit.com/r/kubernetes/comments/w757ju/hostport_vs_nodeport/)
2. [Kubernetes ingress-nginx installation guide](https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/index.md)
3. [K8s ingresss-nginx Helm chart values](https://github.com/kubernetes/ingress-nginx/blob/main/charts/ingress-nginx/values.yaml)
4. [ingress-nginx bare-metal considerations](https://github.com/kubernetes/ingress-nginx/blob/main/docs/deploy/baremetal.md#bare-metal-considerations)
5. [Patch Any Helm Chart Template Using A Kustomize Post-Renderer](https://austindewey.com/2020/07/27/patch-any-helm-chart-template-using-a-kustomize-post-renderer/)
6. [Helm Kustomize example](https://github.com/thomastaylor312/advanced-helm-demos/tree/master/post-render)
7. [Kubernetes Kustomize with JsonPatches6902](https://skryvets.com/blog/2019/05/15/kubernetes-kustomize-json-patches-6902/#append-to-a-list)
8. [JavaScript Object Notation (JSON) Patch 6902](https://www.rfc-editor.org/rfc/rfc6902#section-4.5)
9. [NFS Persistence Storage Basics](https://docs.openshift.com/container-platform/3.11/install_config/persistent_storage/persistent_storage_nfs.html)
10. [NFS based Persistent Volume in Kubernetes example](https://www.linuxtechi.com/configure-nfs-persistent-volume-kubernetes/)
11. [JSON Patch (JsonPatches6902) Builder Online](https://json-patch-builder-online.github.io/)
12. [Convert YAML to JSON online](https://onlineyamltools.com/convert-yaml-to-json)
13. [Convert JSON to YAML online](https://json2yaml.com/)
14. [Modify containers without rebuilding their image](https://blog.cloudowski.com/articles/how-to-modify-containers-wihtout-rebuilding/)
15. [Budibasae - backups](https://docs.budibase.com/docs/backups)
16. [Create missing system DBs in couchdb](https://stackoverflow.com/questions/74338364/how-to-create-users-database-when-launching-couchdb-in-docker-container)
17. [Apache couchdb - release notes](https://docs.couchdb.org/en/stable/whatsnew/3.2.html#version-3-2-2)
18. [My own Budibase app sidecar for admin](https://hub.docker.com/repository/docker/noamasor/budi-cli-sidecar/general)