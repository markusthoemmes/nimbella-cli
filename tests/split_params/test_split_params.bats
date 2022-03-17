load ../test_setup.bash

setup_file() {
	$NIM project deploy $BATS_TEST_DIRNAME
}

teardown_file() {
	delete_package "test_split_params"
}

@test "deploy project with split-level parameters in config" {
	run $NIM action invoke test_split_params/authorize -r
	assert_success
	assert_output --partial '"parameters": [
    {
      "key": "e1",
      "value": "eone"
    },
    {
      "key": "p3",
      "value": "pthree"
    },
    {
      "key": "e3",
      "value": "ethree"
    },
    {
      "key": "p2",
      "value": "ptwo"
    },
    {
      "key": "e2",
      "value": "etwo"
    },
    {
      "key": "p1",
      "value": "pone"
    }
  ]'
}
