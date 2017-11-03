# Copyright 2014, Dell
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

from setuptools import setup

setup(name='cb2_api',
    version='0.0.3',
    description='Python digitalrebar api bindings',
    url='https://github.com/digitalrebar',
    license='Apache2',
    packages=['cb2_api', 'cb2_api.objects', 'cb2_api.examples'],
    install_requires=[
        'requests'],
    )