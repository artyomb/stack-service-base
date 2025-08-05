CI_PROJECT_NAME=service_name
CI_PIPELINE_ID=local
CI_REGISTRY_HOST=localhost

docker run --rm --env-file <(env | grep ^CI_) \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /root/.docker:/root/.docker \
  $(docker build -q -t build/${CI_PROJECT_NAME} -f Dockerfile.build ..) 2>&1

