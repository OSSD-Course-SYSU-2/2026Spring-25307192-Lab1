import display from '@ohos.display';
import promptAction from '@ohos.promptAction';

// 明确限制方向类型，防止严格类型检查报错
type Direction = 'up' | 'down' | 'left' | 'right';

// 方向向量
const DIR_VECTORS: Record<Direction, [number, number]> = {
  'up': [-1, 0],
  'down': [1, 0],
  'left': [0, -1],
  'right': [0, 1]
};

// 游戏地图：1=墙，0=豆子，2=大力丸
const MAP_DATA: string[] = [
  '111111111111111',
  '100000000000001',
  '101110111011101',
  '101000100010001',
  '101010000010101',
  '100010001010001',
  '101110111011101',
  '100000000000001',
  '101110111011101',
  '100010001010001',
  '101010000010101',
  '101000100010001',
  '101110111011101',
  '100000000000001',
  '111111111111111'
];

const MAP_ROWS = MAP_DATA.length;
const MAP_COLS = MAP_DATA[0].length;

const GHOST_COLORS: string[] = ['#FF4444', '#FFB8FF', '#00FFFF', '#FFB852'];
const GHOST_START_POS: [number, number][] = [[6, 7], [7, 6], [7, 8], [8, 7]];
const PACMAN_START: [number, number] = [13, 7];

// 定义幽灵接口
interface Ghost {
  pos: [number, number];
  dir: Direction;
  color: string;
  mode: 'normal' | 'frightened' | 'eaten';
}

@Entry
@Component
struct PacManGame {
  private settings: RenderingContextSettings = new RenderingContextSettings(true);
  private canvasCtx: CanvasRenderingContext2D = new CanvasRenderingContext2D(this.settings);

  @State canvasSize: number = 360;
  @State cellSize: number = 20;

  @State score: number = 0;
  @State lives: number = 3;
  @State level: number = 1;
  @State isPaused: boolean = false;
  @State isGameOver: boolean = false;
  @State isWin: boolean = false;

  private pacPos: [number, number] = [PACMAN_START[0], PACMAN_START[1]];
  private pacDir: Direction = 'left';
  private mouthAngle: number = 0;
  private mouthOpen: boolean = true;

  private dotsEaten: boolean[][] = [];
  private ghosts: Ghost[] = [];
  private powerPellets: Set<string> = new Set();

  private frightenedEndTime: number = 0;
  private frightenedDuration: number = 7000;

  private ghostTimer: number = -1; // 幽灵独立的移动定时器
  private animTimer: number = -1;

  // 初始化游戏数据
  private initGameData() {
    this.score = 0;
    this.lives = 3;
    this.level = 1;
    this.isPaused = false;
    this.isGameOver = false;
    this.isWin = false;

    this.pacPos = [PACMAN_START[0], PACMAN_START[1]];
    this.pacDir = 'left';
    this.mouthAngle = 0;

    this.dotsEaten = Array(MAP_ROWS).fill(false).map(() => Array(MAP_COLS).fill(false));
    this.powerPellets.clear();
    for (let r = 0; r < MAP_ROWS; r++) {
      for (let c = 0; c < MAP_COLS; c++) {
        if (MAP_DATA[r][c] === '2') {
          this.powerPellets.add(`${r},${c}`);
        }
      }
    }

    // 初始化幽灵
    this.ghosts = [];
    for (let i = 0; i < GHOST_START_POS.length; i++) {
      let ghost: Ghost = {
        pos: [GHOST_START_POS[i][0], GHOST_START_POS[i][1]],
        dir: 'up',
        color: GHOST_COLORS[i],
        mode: 'normal'
      };
      this.ghosts.push(ghost);
    }
    this.frightenedEndTime = 0;
  }

  private isWall(r: number, c: number): boolean {
    return r < 0 || r >= MAP_ROWS || c < 0 || c >= MAP_COLS || MAP_DATA[r][c] === '1';
  }

  private canMove(r: number, c: number): boolean {
    return !this.isWall(r, c);
  }

  private resetPositions() {
    this.pacPos = [PACMAN_START[0], PACMAN_START[1]];
    this.pacDir = 'left';
    for (let i = 0; i < this.ghosts.length; i++) {
      this.ghosts[i].pos = [GHOST_START_POS[i][0], GHOST_START_POS[i][1]];
      this.ghosts[i].dir = 'up';
      this.ghosts[i].mode = 'normal';
    }
    this.frightenedEndTime = 0;
  }

  // 点击方向键时直接触发该函数：按一次，动一格
  private handlePacmanStep(dir: Direction) {
    if (this.isPaused || this.isGameOver || this.isWin) return;

    this.pacDir = dir;
    let vec = DIR_VECTORS[dir];
    let nextRow = this.pacPos[0] + vec[0];
    let nextCol = this.pacPos[1] + vec[1];

    if (this.canMove(nextRow, nextCol)) {
      this.pacPos = [nextRow, nextCol];
      // 嘴巴咬合动画激活动作
      this.mouthOpen = !this.mouthOpen;
      this.mouthAngle = this.mouthOpen ? 0.2 * Math.PI : 0.05 * Math.PI;

      // 移动后立刻结算机制
      this.handleEating();
      this.checkCollision();
      this.checkLevelComplete();
      this.drawGame();
    }
  }

  private handleEating() {
    let r = this.pacPos[0];
    let c = this.pacPos[1];
    let cell = MAP_DATA[r][c];

    if (cell === '0' && !this.dotsEaten[r][c]) {
      this.dotsEaten[r][c] = true;
      this.score += 10;
    }

    if (cell === '2' && this.powerPellets.has(`${r},${c}`)) {
      this.powerPellets.delete(`${r},${c}`);
      this.score += 50;
      this.frightenedEndTime = Date.now() + this.frightenedDuration;
      for (let i = 0; i < this.ghosts.length; i++) {
        if (this.ghosts[i].mode !== 'eaten') {
          this.ghosts[i].mode = 'frightened';
          this.ghosts[i].dir = this.getOppositeDir(this.ghosts[i].dir);
        }
      }
    }
  }

  private getOppositeDir(dir: Direction): Direction {
    if (dir === 'up') return 'down';
    if (dir === 'down') return 'up';
    if (dir === 'left') return 'right';
    return 'left';
  }

  // 幽灵专用的主循环
  private ghostLoop = () => {
    if (this.isPaused || this.isGameOver || this.isWin) return;
    this.moveGhosts();
    this.checkCollision();
    this.checkLevelComplete();
    this.drawGame();
  };

  private moveGhosts() {
    let now = Date.now();
    let isFrightened = now < this.frightenedEndTime;
    let dirKeys: Direction[] = ['up', 'down', 'left', 'right'];

    for (let i = 0; i < this.ghosts.length; i++) {
      let ghost = this.ghosts[i];
      if (ghost.mode === 'frightened' && !isFrightened) {
        ghost.mode = 'normal';
      }
      if (ghost.mode === 'eaten') {
        let target = GHOST_START_POS[i];
        if (ghost.pos[0] === target[0] && ghost.pos[1] === target[1]) {
          ghost.mode = 'normal';
        }
      }

      let possibleDirs: Direction[] = [];
      for (let d = 0; d < dirKeys.length; d++) {
        let dir = dirKeys[d];
        let vec = DIR_VECTORS[dir];
        let nr = ghost.pos[0] + vec[0];
        let nc = ghost.pos[1] + vec[1];
        if (this.canMove(nr, nc) && dir !== this.getOppositeDir(ghost.dir)) {
          possibleDirs.push(dir);
        }
      }
      if (possibleDirs.length === 0) {
        for (let d = 0; d < dirKeys.length; d++) {
          let dir = dirKeys[d];
          let vec = DIR_VECTORS[dir];
          let nr = ghost.pos[0] + vec[0];
          let nc = ghost.pos[1] + vec[1];
          if (this.canMove(nr, nc)) {
            possibleDirs.push(dir);
          }
        }
      }

      if (possibleDirs.length > 0) {
        if (ghost.mode === 'normal' && Math.random() < 0.3) {
          let bestDir = possibleDirs[0];
          let minDist = 9999;
          for (let d = 0; d < possibleDirs.length; d++) {
            let dir = possibleDirs[d];
            let vec = DIR_VECTORS[dir];
            let nr = ghost.pos[0] + vec[0];
            let nc = ghost.pos[1] + vec[1];
            let dist = Math.abs(nr - this.pacPos[0]) + Math.abs(nc - this.pacPos[1]);
            if (dist < minDist) {
              minDist = dist;
              bestDir = dir;
            }
          }
          ghost.dir = bestDir;
        } else {
          ghost.dir = possibleDirs[Math.floor(Math.random() * possibleDirs.length)];
        }
      }

      let moveVec = DIR_VECTORS[ghost.dir];
      let newRow = ghost.pos[0] + moveVec[0];
      let newCol = ghost.pos[1] + moveVec[1];
      if (this.canMove(newRow, newCol)) {
        ghost.pos = [newRow, newCol];
      }
    }
  }

  private checkCollision() {
    let pr = this.pacPos[0];
    let pc = this.pacPos[1];
    for (let i = 0; i < this.ghosts.length; i++) {
      let ghost = this.ghosts[i];
      if (ghost.pos[0] === pr && ghost.pos[1] === pc) {
        if (ghost.mode === 'frightened') {
          this.score += 200;
          ghost.mode = 'eaten';
          ghost.pos = [GHOST_START_POS[i][0], GHOST_START_POS[i][1]];
        } else if (ghost.mode === 'normal') {
          this.lives--;
          if (this.lives <= 0) {
            this.isGameOver = true;
            this.stopTimers();
            try {
              let toastOpts: promptAction.ShowToastOptions = { message: '游戏结束', duration: 2000 };
              promptAction.showToast(toastOpts);
            } catch {}
          } else {
            this.resetPositions();
            try {
              let toastOpts: promptAction.ShowToastOptions = { message: '失去一条命！', duration: 1500 };
              promptAction.showToast(toastOpts);
            } catch {}
          }
          return;
        }
      }
    }
  }

  private getRemainingDots(): number {
    let count = 0;
    for (let r = 0; r < MAP_ROWS; r++) {
      for (let c = 0; c < MAP_COLS; c++) {
        let char = MAP_DATA[r][c];
        if ((char === '0' && !this.dotsEaten[r][c]) || (char === '2' && this.powerPellets.has(`${r},${c}`))) {
          count++;
        }
      }
    }
    return count;
  }

  private checkLevelComplete() {
    if (this.getRemainingDots() === 0) {
      this.level++;
      if (this.level > 3) {
        this.isWin = true;
        this.stopTimers();
        return;
      }
      this.dotsEaten = Array(MAP_ROWS).fill(false).map(() => Array(MAP_COLS).fill(false));
      this.powerPellets.clear();
      for (let r = 0; r < MAP_ROWS; r++) {
        for (let c = 0; c < MAP_COLS; c++) {
          if (MAP_DATA[r][c] === '2') {
            this.powerPellets.add(`${r},${c}`);
          }
        }
      }
      this.resetPositions();
      try {
        let toastOpts: promptAction.ShowToastOptions = { message: `进入第 ${this.level} 关！`, duration: 2000 };
        promptAction.showToast(toastOpts);
      } catch {}
    }
  }

  private animationLoop = () => {
    if (this.isPaused || this.isGameOver || this.isWin) return;
    this.drawGame();
  };

  private drawGame() {
    let ctx = this.canvasCtx;
    let size = this.canvasSize;
    let cell = this.cellSize;

    ctx.clearRect(0, 0, size, size);
    ctx.fillStyle = '#0a0a1a';
    ctx.fillRect(0, 0, size, size);

    // 迷宫
    for (let r = 0; r < MAP_ROWS; r++) {
      for (let c = 0; c < MAP_COLS; c++) {
        let x = c * cell;
        let y = r * cell;
        let char = MAP_DATA[r][c];
        if (char === '1') {
          ctx.fillStyle = '#2121a0';
          ctx.fillRect(x + 1, y + 1, cell - 2, cell - 2);
          ctx.fillStyle = '#3a3acc';
          ctx.fillRect(x + 2, y + 2, cell - 4, cell - 4);
        } else if (char === '0' && !this.dotsEaten[r][c]) {
          ctx.fillStyle = '#ffccaa';
          ctx.beginPath();
          ctx.arc(x + cell / 2, y + cell / 2, cell * 0.15, 0, Math.PI * 2);
          ctx.fill();
        } else if (char === '2' && this.powerPellets.has(`${r},${c}`)) {
          let flash = Math.floor(Date.now() / 300) % 2 === 0;
          ctx.fillStyle = flash ? '#ffaa00' : '#ffdd77';
          ctx.beginPath();
          ctx.arc(x + cell / 2, y + cell / 2, cell * 0.3, 0, Math.PI * 2);
          ctx.fill();
          ctx.fillStyle = '#fff';
          ctx.beginPath();
          ctx.arc(x + cell / 2, y + cell / 2, cell * 0.12, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    }

    // 幽灵
    for (let i = 0; i < this.ghosts.length; i++) {
      let ghost = this.ghosts[i];
      let gr = ghost.pos[0];
      let gc = ghost.pos[1];
      let gx = gc * cell + cell / 2;
      let gy = gr * cell + cell / 2;
      let radius = cell * 0.4;

      ctx.save();
      ctx.translate(gx, gy);

      if (ghost.mode === 'frightened') {
        let flicker = Math.floor(Date.now() / 200) % 2 === 0;
        ctx.fillStyle = flicker ? '#2121ff' : '#ffffff';
      } else if (ghost.mode === 'eaten') {
        ctx.fillStyle = '#555555';
      } else {
        ctx.fillStyle = ghost.color;
      }

      ctx.beginPath();
      ctx.arc(0, -radius * 0.2, radius, Math.PI, 0);
      ctx.lineTo(radius, radius * 0.8);
      let waves = 3;
      let waveWidth = (radius * 2) / waves;
      for (let w = 0; w < waves; w++) {
        let sx = radius - w * waveWidth;
        let sy = radius * 0.8;
        ctx.quadraticCurveTo(sx - waveWidth / 2, radius * 1.2, sx - waveWidth, sy);
      }
      ctx.lineTo(-radius, radius * 0.8);
      ctx.closePath();
      ctx.fill();

      ctx.fillStyle = '#ffffff';
      ctx.beginPath();
      ctx.arc(-radius * 0.35, -radius * 0.3, radius * 0.25, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(radius * 0.35, -radius * 0.3, radius * 0.25, 0, Math.PI * 2);
      ctx.fill();

      ctx.fillStyle = '#0000aa';
      ctx.beginPath();
      ctx.arc(-radius * 0.35, -radius * 0.35, radius * 0.12, 0, Math.PI * 2);
      ctx.fill();
      ctx.beginPath();
      ctx.arc(radius * 0.35, -radius * 0.35, radius * 0.12, 0, Math.PI * 2);
      ctx.fill();

      ctx.restore();
    }

    // 吃豆人
    let pr = this.pacPos[0];
    let pc = this.pacPos[1];
    let px = pc * cell + cell / 2;
    let py = pr * cell + cell / 2;
    let pRadius = cell * 0.4;

    ctx.save();
    ctx.translate(px, py);
    let rotation = 0;
    if (this.pacDir === 'right') rotation = 0;
    else if (this.pacDir === 'down') rotation = Math.PI / 2;
    else if (this.pacDir === 'left') rotation = Math.PI;
    else if (this.pacDir === 'up') rotation = -Math.PI / 2;
    ctx.rotate(rotation);

    ctx.fillStyle = '#ffff00';
    ctx.beginPath();
    ctx.moveTo(0, 0);
    ctx.arc(0, 0, pRadius, this.mouthAngle, 2 * Math.PI - this.mouthAngle);
    ctx.lineTo(0, 0);
    ctx.fill();

    ctx.fillStyle = '#000';
    ctx.beginPath();
    ctx.arc(0, -pRadius * 0.4, pRadius * 0.15, 0, Math.PI * 2);
    ctx.fill();
    ctx.restore();

    // UI文字
    ctx.fillStyle = '#ffffff';
    ctx.font = `${cell * 0.7}px sans-serif`;
    ctx.fillText(`分数: ${this.score}`, 10, cell * 0.9);
    ctx.fillText(`关卡: ${this.level}`, 10, cell * 1.8);

    for (let i = 0; i < this.lives; i++) {
      ctx.fillStyle = '#ffff00';
      ctx.beginPath();
      ctx.arc(size - 20 - i * 25, 15, 8, 0, Math.PI * 2);
      ctx.fill();
    }

    // 暂停/结束/胜利提示
    if (this.isPaused) {
      ctx.fillStyle = 'rgba(0,0,0,0.6)';
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#ffffff';
      ctx.font = `${cell * 1.2}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillText('暂停中', size / 2, size / 2);
    } else if (this.isGameOver) {
      ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#ff4444';
      ctx.font = `bold ${cell * 1.5}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillText('游戏结束', size / 2, size / 2 - 10);
      ctx.fillStyle = '#ffffff';
      ctx.font = `${cell * 0.8}px sans-serif`;
      ctx.fillText(`得分: ${this.score}`, size / 2, size / 2 + 20);
    } else if (this.isWin) {
      ctx.fillStyle = 'rgba(0,0,0,0.7)';
      ctx.fillRect(0, 0, size, size);
      ctx.fillStyle = '#ffdd57';
      ctx.font = `bold ${cell * 1.5}px sans-serif`;
      ctx.textAlign = 'center';
      ctx.fillText('恭喜通关！', size / 2, size / 2 - 10);
      ctx.fillStyle = '#ffffff';
      ctx.font = `${cell * 0.8}px sans-serif`;
      ctx.fillText(`得分: ${this.score}`, size / 2, size / 2 + 20);
    }
  }

  private startTimers() {
    this.stopTimers();
    // 幽灵速度降低：从原先的 180ms 调慢到 500ms 走一格
    this.ghostTimer = setInterval(this.ghostLoop, 500);
    this.animTimer = setInterval(this.animationLoop, 100);
  }

  private stopTimers() {
    if (this.ghostTimer !== -1) {
      clearInterval(this.ghostTimer);
      this.ghostTimer = -1;
    }
    if (this.animTimer !== -1) {
      clearInterval(this.animTimer);
      this.animTimer = -1;
    }
  }

  private togglePause() {
    if (this.isGameOver || this.isWin) return;
    this.isPaused = !this.isPaused;
    if (this.isPaused) {
      this.stopTimers();
    } else {
      this.startTimers();
    }
    this.drawGame();
  }

  private restartGame() {
    this.stopTimers();
    this.initGameData();
    this.startTimers();
    this.drawGame();
  }

  aboutToAppear() {
    try {
      let displayInfo = display.getDefaultDisplaySync();
      let screenWidth = displayInfo.width;
      this.canvasSize = Math.min(screenWidth * 0.9, 500);
    } catch {
      this.canvasSize = 360;
    }
    this.cellSize = this.canvasSize / MAP_COLS;
    this.initGameData();
  }

  onPageShow() {
    this.startTimers();
  }

  onPageHide() {
    this.stopTimers();
  }

  aboutToDisappear() {
    this.stopTimers();
  }

  build() {
    Column() {
      Text('🍒 吃豆人 PAC-MAN')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFDD57')
        .margin({ top: 20, bottom: 10 })

      Canvas(this.canvasCtx)
        .width(this.canvasSize)
        .height(this.canvasSize)
        .backgroundColor('#000000')
        .borderRadius(12)
        .shadow({ radius: 20, color: '#4444aa' })
        .onReady(() => {
          this.drawGame();
        })

      Column() {
        Button('▲')
          .width(60).height(60).fontSize(28)
          .backgroundColor('#333388').borderRadius(30)
          .onClick(() => { this.handlePacmanStep('up'); }) // 按下直接前进一步
        Row() {
          Button('◀')
            .width(60).height(60).fontSize(28)
            .backgroundColor('#333388').borderRadius(30)
            .onClick(() => { this.handlePacmanStep('left'); })
          Button('▼')
            .width(60).height(60).fontSize(28)
            .backgroundColor('#333388').borderRadius(30)
            .margin({ left: 20, right: 20 })
            .onClick(() => { this.handlePacmanStep('down'); })
          Button('▶')
            .width(60).height(60).fontSize(28)
            .backgroundColor('#333388').borderRadius(30)
            .onClick(() => { this.handlePacmanStep('right'); })
        }
      }
      .margin({ top: 15 })

      Row() {
        Button('⏯️ 暂停')
          .fontSize(16)
          .backgroundColor('#FF8C00')
          .borderRadius(20)
          .padding({ left: 20, right: 20 })
          .onClick(() => this.togglePause())
        Button('🔄 新游戏')
          .fontSize(16)
          .backgroundColor('#FF4444')
          .borderRadius(20)
          .padding({ left: 20, right: 20 })
          .margin({ left: 20 })
          .onClick(() => this.restartGame())
      }
      .margin({ top: 15, bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .backgroundColor('#0A0A1A')
  }
}