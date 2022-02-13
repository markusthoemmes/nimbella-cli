load ../test_setup.bash

teardown_file() {
  delete_package "test-remote-build-go"
}

@test "deploy go projects with remote build" {
  run $NIM project deploy $BATS_TEST_DIRNAME --remote-build
	assert_success
	assert_line -p "Submitted action 'default' for remote building and deployment in runtime go:default"
}

@test "invoke remotely built go lang actions" {
	test_binary_action test-remote-build-go/default "Hello, stranger!"
}
