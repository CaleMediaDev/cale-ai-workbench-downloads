"""Check the anonymous links people actually use after a Pages deployment."""
from html.parser import HTMLParser
from pathlib import Path
import shutil
import subprocess
from urllib.parse import urljoin
from urllib.request import Request, urlopen

REPO = "https://github.com/CaleMediaDev/cale-ai-workbench-downloads"
SITE = "https://calemediadev.github.io/cale-ai-workbench-downloads/"
FILM = SITE + "films/last-light-at-the-rink.mp4"


class Links(HTMLParser):
    def __init__(self, url):
        super().__init__()
        self.url = url
        self.hrefs = []
        self.players = []
        self.posters = []

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if tag == "a" and "href" in data:
            self.hrefs.append(urljoin(self.url, data["href"]))
        if tag == "img" and data.get("alt") == "Play Last Light at the Rink with sound":
            self.posters.append(urljoin(self.url, data["src"]))
        if tag == "video" and data.get("id") == "watch":
            self.players.append(urljoin(self.url, data["src"]))


def read_page(url):
    parser = Links(url)
    with urlopen(url, timeout=25) as response:
        parser.feed(response.read().decode())
    return parser


readme = read_page(REPO)
assert FILM in readme.hrefs and SITE + "#watch" in readme.hrefs
assert len(readme.posters) == 1
with urlopen(readme.posters[0], timeout=25) as poster:
    assert poster.headers.get_content_type() == "image/jpeg" and poster.read(2) == b"\xff\xd8"
player = read_page(SITE)
assert player.players == [FILM] and FILM in player.hrefs
with urlopen(Request(FILM, headers={"Range": "bytes=0-31"}), timeout=25) as response:
    assert response.status == 206 and response.headers.get_content_type() == "video/mp4"
    assert response.read(12)[4:8] == b"ftyp"
with urlopen(FILM, timeout=30) as media, Path("concert-test.mp4").open("xb") as output:
    shutil.copyfileobj(media, output)
subprocess.run(["ffmpeg", "-v", "error", "-xerror", "-i", "concert-test.mp4",
                "-map", "0:v:0", "-map", "0:a:0", "-f", "null", "-"], check=True)
print("Public README, poster, player, seeking, audio and full video decode passed.")
