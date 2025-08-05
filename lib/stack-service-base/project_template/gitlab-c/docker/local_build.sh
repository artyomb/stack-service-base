CI_PROJECT_NAME=${service_name}
export CI_PIPELINE_ID=local
export CI_PIPELINE_IID=0
export CI_REGISTRY_HOST=localhost

#  -v /root/.docker:/root/.docker \
docker run --rm --env-file <(env | grep ^CI_) \
  -v /var/run/docker.sock:/var/run/docker.sock \
  $(docker build -q -t build/${CI_PROJECT_NAME} -f Dockerfile.build ..) 2>&1

