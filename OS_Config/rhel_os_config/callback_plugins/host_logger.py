# host_logger_v1_updated.py (per-host directory version)
##Logs are stored under with timestamp /data/automation/os_config/ubuntu_os_config/callback_plugins/Ansible_logs
import os, datetime
from ansible.plugins.callback import CallbackBase

class CallbackModule(CallbackBase):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = 'aggregate'
    CALLBACK_NAME = 'host_logger'
    CALLBACK_NEEDS_WHITELIST = True

    def __init__(self):
        super(CallbackModule, self).__init__()
        self.base_dir = '/data/automation/os_config/ubuntu_os_config/callback_plugins/Ansible_logs'
        os.makedirs(self.base_dir, exist_ok=True)
        self.date = datetime.datetime.now().strftime("%d%b%Y")
        self.start_times = {}

    def _host_dir(self, host):
        """Return per-host directory and ensure it exists"""
        path = os.path.join(self.base_dir, host)
        os.makedirs(path, exist_ok=True)
        return path

    # def _log(self, host, message):
    #     host_dir = self._host_dir(host)
    #     path = os.path.join(host_dir, f"{host}_log_{self.date}.txt")
    #     with open(path, "a") as f:
    #         f.write(message + "\n")

    def _log(self, host, message):
        host_dir = self._host_dir(host)
        path = os.path.join(host_dir, f"{host}_log_{self.date}.txt")

        timestamp = datetime.datetime.now().strftime("%H:%M:%S")
        with open(path, "a") as f:
            f.write(f"[{timestamp}] {message}\n")


    def v2_playbook_on_start(self, playbook):
        self._log("GLOBAL", f"=== PLAYBOOK START: {playbook._file_name} ({datetime.datetime.now().strftime('%H:%M:%S')}) ===")

    def v2_playbook_on_stats(self, stats):
        self._log("GLOBAL", f"=== PLAYBOOK END ({datetime.datetime.now().strftime('%H:%M:%S')}) ===")

    def v2_runner_on_ok(self, result):
        if result.task_name.lower().startswith(("meta", "debug", "gathering facts")):
            return
        duration = ""
        if result.task_name in self.start_times:
            elapsed = (datetime.datetime.now() - self.start_times[result.task_name]).total_seconds()
            duration = f" ({elapsed:.1f}s)"
        self._log(result._host.get_name(), f"✅ SUCCESS: {result.task_name}{duration}")

    def v2_runner_on_failed(self, result, ignore_errors=False):
        if result.task_name.lower().startswith(("meta", "debug", "gathering facts")):
            return
        msg = f"❌ FAILED: {result.task_name}"
        if result._result.get('msg'):
            msg += f" → {result._result['msg']}"
        self._log(result._host.get_name(), msg)

    def v2_runner_on_skipped(self, result):
        if result.task_name.lower().startswith(("meta", "debug", "gathering facts")):
            return
        self._log(result._host.get_name(), f"⚠️ SKIPPED: {result.task_name}")

    def v2_runner_on_start(self, host, task):
        self.start_times[task.get_name()] = datetime.datetime.now()

