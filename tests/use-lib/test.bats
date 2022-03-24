load ../test_setup.bash

teardown_file() {
	delete_package "test-use-lib"
}

@test "Test local deployment with a lib build" {
  rm -f "$BATS_TEST_DIRNAME/lib/hello.js"
  run $NIM project deploy "$BATS_TEST_DIRNAME"
	assert_success
  assert_output --partial "Deployed actions"
	refute_output --partial "Error"
}

@test "Test that first deployment succeeded" {
  run $NIM action invoke test-use-lib/hello1
	assert_output --partial "Hello stranger!"
  run $NIM action invoke test-use-lib/hello2
	assert_output --partial "Hello stranger!"
  run $NIM action invoke test-use-lib/hello3
	assert_output --partial "Hello stranger!"
}

@test "Test remote deployment with a lib build" {
  rm -f "$BATS_TEST_DIRNAME/lib/hello.js"
  delete_package "test-use-lib"
  run $NIM project deploy "$BATS_TEST_DIRNAME" --remote-build
	assert_success
  assert_output --partial "Deployed actions"
	refute_output --partial "Error"
}

@test "Test that second deployment succeeded" {
  run $NIM action invoke test-use-lib/hello1
	assert_output --partial "Hello stranger!"
  run $NIM action invoke test-use-lib/hello2
	assert_output --partial "Hello stranger!"
  run $NIM action invoke test-use-lib/hello3
	assert_output --partial "Hello stranger!"
}
