# -*- coding: iso-8859-1 -*-
# Maintainer: joaander

from hoomd_script import *
import unittest
import os
import tempfile

# unit tests for analyze.log
class analyze_log_tests (unittest.TestCase):
    def setUp(self):
        print
        init.create_random(N=100, phi_p=0.05);

        sorter.set_params(grid=8)

        if comm.get_rank() == 0:
            tmp = tempfile.mkstemp(suffix='.test.log');
            self.tmp_file = tmp[1];
        else:
            self.tmp_file = "invalid";

    # tests basic creation of the analyzer
    def test(self):
        analyze.log(quantities = ['test1', 'test2', 'test3'], period = 10, filename=self.tmp_file);
        run(100);

    # tests with phase
    def test_phase(self):
        analyze.log(quantities = ['test1', 'test2', 'test3'], period = 10, filename=self.tmp_file, phase=0);
        run(100);

    # test set_params
    def test_set_params(self):
        ana = analyze.log(quantities = ['test1', 'test2', 'test3'], period = 10, filename=self.tmp_file);
        ana.set_params(quantities = ['test1']);
        run(100);
        ana.set_params(delimiter = ' ');
        run(100);
        ana.set_params(quantities = ['test2', 'test3'], delimiter=',')
        run(100);

    # test variable period
    def test_variable(self):
        ana = analyze.log(quantities = ['test1', 'test2', 'test3'], period = lambda n: n*10, filename=self.tmp_file);
        run(100);

    # test the initialization checks
    def test_init_checks(self):
        ana = analyze.log(quantities = ['test1', 'test2', 'test3'], period = 10, filename=self.tmp_file);
        ana.cpp_analyzer = None;

        self.assertRaises(RuntimeError, ana.enable);
        self.assertRaises(RuntimeError, ana.disable);

    def tearDown(self):
        init.reset();
        if (comm.get_rank()==0):
            os.remove(self.tmp_file);


if __name__ == '__main__':
    unittest.main(argv = ['test.py', '-v'])
