load ../test_setup.bash

teardown_file() {
  delete_package "test-remote-build-go"
}

@test "deploy go projects with remote build" {
  run $NIM project deploy $BATS_TEST_DIRNAME --remote-build
	assert_success
	assert_line -p "Submitted action 'dependencies-1.15' for remote building and deployment in runtime go:1.15"
}

@test "invoke remotely built go lang actions" {
	test_binary_action test-remote-build-go/dependencies-1.15 "Hello, stranger! (go1.15."
}
